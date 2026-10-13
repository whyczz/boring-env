import json, os, sys, unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import value  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def dur(start, end, val, filed="2025-01-01", accn="a"):
    return {"start": start, "end": end, "val": val, "filed": filed, "accn": accn}


def inst(end, val, filed="2025-01-01", accn="a"):
    return {"end": end, "val": val, "filed": filed, "accn": accn}


def facts(**tags):
    out = {"us-gaap": {}, "dei": {}}
    for tag, rows in tags.items():
        ns, _, name = tag.rpartition("__")
        unit = "shares" if "Shares" in name else "USD"
        out[ns or "us-gaap"][name] = {"units": {unit: rows}}
    return {"facts": out}


SRC = value.load_json(os.path.join(HERE, "..", "sources.json"))


class Flow(unittest.TestCase):
    def test_ttm_from_ytd(self):
        f = facts(Revenues=[
            dur("2022-01-01", "2022-12-31", 80),
            dur("2023-01-01", "2023-12-31", 100),
            dur("2023-01-01", "2023-06-30", 45),
            dur("2024-01-01", "2024-06-30", 60),
            dur("2022-01-01", "2022-06-30", 35),
        ])
        ttm, prior = value.flow(f, "Revenues")
        self.assertEqual(ttm, 115)          # 100 + 60 - 45
        self.assertEqual(prior, 90)         # 80 + 45 - 35

    def test_annual_only(self):
        f = facts(Revenues=[dur("2022-01-01", "2022-12-31", 80), dur("2023-01-01", "2023-12-31", 100)])
        self.assertEqual(value.flow(f, "Revenues"), (100, 80))

    def test_restated_value_wins(self):
        f = facts(Revenues=[dur("2023-01-01", "2023-12-31", 100, "2024-02-01"),
                            dur("2023-01-01", "2023-12-31", 97, "2025-02-01")])
        self.assertEqual(value.flow(f, "Revenues")[0], 97)

    def test_newest_tag_wins(self):
        f = facts(SalesRevenueNet=[dur("2015-01-01", "2015-12-31", 5)],
                  Revenues=[dur("2023-01-01", "2023-12-31", 100)])
        self.assertEqual(value.resolve(f, SRC["flows"]["revenue"], "flow")[0], 100)


class Instant(unittest.TestCase):
    def test_share_classes_summed(self):
        f = facts(dei__EntityCommonStockSharesOutstanding=[
            inst("2024-01-31", 6, accn="new"), inst("2024-01-31", 4, accn="new"), inst("2023-01-31", 9, accn="old")])
        self.assertEqual(value.resolve(f, SRC["instants"]["shares"], "instant"), 10)

    def test_debt_sum(self):
        f = facts(LongTermDebtNoncurrent=[inst("2023-12-31", 50)], LongTermDebtCurrent=[inst("2023-12-31", 5)])
        self.assertEqual(value.resolve(f, SRC["instants"]["debt"], "instant"), 55)


class Metrics(unittest.TestCase):
    def setUp(self):
        y = lambda v23, v22: [dur("2022-01-01", "2022-12-31", v22), dur("2023-01-01", "2023-12-31", v23)]
        self.f = facts(
            Revenues=y(1000, 800), GrossProfit=y(600, 480), OperatingIncomeLoss=y(200, 150),
            NetIncomeLoss=y(150, 100), NetCashProvidedByUsedInOperatingActivities=y(250, 200),
            PaymentsToAcquirePropertyPlantAndEquipment=y(50, 40), DepreciationDepletionAndAmortization=y(30, 25),
            ShareBasedCompensation=y(20, 15), WeightedAverageNumberOfDilutedSharesOutstanding=y(105, 100),
            CashAndCashEquivalentsAtCarryingValue=[inst("2023-12-31", 300)],
            LongTermDebtNoncurrent=[inst("2023-12-31", 100)], StockholdersEquity=[inst("2023-12-31", 500)],
            dei__EntityCommonStockSharesOutstanding=[inst("2024-01-31", 100)],
        )

    def test_ratios(self):
        lens = value.load_json(os.path.join(HERE, "..", "lenses", "shkreli.json"))
        m = value.metrics(self.f, SRC, 20.0, lens)
        self.assertAlmostEqual(m["revenue_growth"], 0.25)
        self.assertAlmostEqual(m["gross_margin"], 0.6)
        self.assertAlmostEqual(m["dilution"], 0.05)
        self.assertEqual(m["fcf"], 200)
        self.assertEqual(m["net_cash"], 200)
        self.assertEqual(m["market_cap"], 2000)
        self.assertEqual(m["ev"], 1800)
        self.assertAlmostEqual(m["ev_ebit"], 9)
        self.assertAlmostEqual(m["fcf_yield"], 0.1)
        self.assertIsNone(m["runway_q"])
        self.assertGreater(m["dcf_value"], 0)
        self.assertAlmostEqual(m["multiple_value"], (200 * 15 + 200) / 100)

    def test_overrides_change_dcf(self):
        lens = value.load_json(os.path.join(HERE, "..", "lenses", "roaring-kitty.json"))
        lo = value.metrics(self.f, SRC, 20.0, lens)["dcf_value"]
        hi = value.metrics(self.f, SRC, 20.0, lens, {"growth": "0.2"})["dcf_value"]
        self.assertGreater(hi, lo)

    def test_score(self):
        rules = [{"metric": "x", "op": ">=", "value": 1, "points": 2, "flag": "big"},
                 {"metric": "y", "op": "<", "value": 0, "points": -1, "flag": "neg"},
                 {"metric": "z", "op": ">", "value": 0, "points": 5, "flag": "missing"}]
        self.assertEqual(value.score({"x": 1, "y": -1, "z": None}, rules), (1, "big; neg"))

    def test_lens_columns_are_computed(self):
        lens_dir = os.path.join(HERE, "..", "lenses")
        for name in os.listdir(lens_dir):
            lens = value.load_json(os.path.join(lens_dir, name))
            m = value.metrics(self.f, SRC, 20.0, lens)
            m.update(ticker="X", name="X", score=0, flags="")
            missing = [c for c in lens["columns"] + [r["metric"] for r in lens["rules"]] if c not in m]
            self.assertEqual(missing, [], name)


class Dcf(unittest.TestCase):
    def test_known_value(self):
        # 1 year, no growth, 10% discount, 10x terminal: (100/1.1 + 1000/1.1) / 10 shares
        self.assertAlmostEqual(value.dcf(100, 10, 0, 1, 0, 0.10, 10), 100.0)

    def test_implied_growth_round_trips(self):
        price = value.dcf(100, 10, 50, 5, 0.12, 0.10, 15)
        self.assertAlmostEqual(value.implied_growth(price, 100, 10, 50, 5, 0.10, 15), 0.12, places=6)

    def test_negative_base_has_no_value(self):
        self.assertIsNone(value.dcf(-5, 10, 0, 5, 0.1, 0.1, 10))


if __name__ == "__main__":
    unittest.main()
