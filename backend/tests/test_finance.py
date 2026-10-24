import pytest

from huddle import engine, finance
from huddle.templates.car import ASSUME

from test_engine import family


def test_monthly_payment_matches_textbook_value():
    # $30,000 at 6% APR over 60 months is the standard $579.98 example.
    assert finance.monthly_payment(30000, 0.06, 60) == pytest.approx(579.98, abs=0.01)


def test_zero_apr_is_straight_division():
    assert finance.monthly_payment(12000, 0, 48) == 250


def test_balance_runs_to_zero_and_payments_cover_principal_plus_interest():
    p, apr, n = 25000, 0.07, 48
    assert finance.balance_after(p, apr, n, 0) == pytest.approx(p)
    assert finance.balance_after(p, apr, n, n) == pytest.approx(0, abs=0.01)
    pmt = finance.monthly_payment(p, apr, n)
    # Principal repaid after 24 payments equals payments made minus interest accrued month by month.
    bal, interest = p, 0.0
    for _ in range(24):
        i = bal * apr / 12
        interest += i
        bal -= pmt - i
    assert finance.balance_after(p, apr, n, 24) == pytest.approx(bal, abs=0.01)


def test_lease_payment_is_depreciation_plus_rent_charge():
    # cap 30,000, residual 18,000: (12,000 / 36) + (48,000 * 0.0025) = 333.33 + 120
    assert finance.lease_payment(30000, 0.60, 0.0025, 36) == pytest.approx(453.33, abs=0.01)
    assert finance.lease_payment(30000, 0.60, 0.0025, 36, tax_pct=0.10) == pytest.approx(498.67, abs=0.01)


def test_money_factor_to_apr():
    assert finance.apr_from_money_factor(0.0025) == pytest.approx(0.06)


def test_compare_is_internally_consistent():
    c = finance.compare(32850, **ASSUME)
    for plan in ("cash", "finance", "lease"):
        p = c[plan]
        assert p["net_cost"] == pytest.approx(p["total_paid"] - p["equity"], abs=1)
    assert c["lease"]["equity"] == 0 and c["cash"]["interest"] == 0
    assert c["finance"]["loan_total_interest"] > c["finance"]["interest"] > 0
    assert c["best"] == min(("cash", "finance", "lease"), key=lambda k: c[k]["net_cost"])


def test_free_money_makes_finance_beat_cash_is_not_worse():
    # At 0% APR, financing can never cost more than paying cash over the same term.
    c = finance.compare(30000, **{**ASSUME, "apr": 0})
    assert c["finance"]["net_cost"] <= c["cash"]["net_cost"]


@pytest.mark.parametrize("args", [(-1, 0.05, 60), (1000, -0.01, 60), (1000, 0.05, 0)])
def test_bad_loan_inputs_raise(args):
    with pytest.raises(ValueError):
        finance.monthly_payment(*args)


def test_bad_lease_inputs_raise():
    with pytest.raises(ValueError):
        finance.lease_payment(30000, 1.2, 0.0025, 36)


def test_private_explanation_uses_only_computed_numbers_and_own_budget():
    s = family()
    top = engine.run(s)
    text = engine.explain_option(s, "mom", top[0]["name"])
    f = top[0]["finance"]
    assert f"${f['lease']['monthly']:,}" in text and f"${f['finance']['monthly']:,}" in text
    assert "$650/mo limit" in text          # Mom's own limit, in Mom's own thread
    assert "900" not in text                # never Dad's
    assert s.threads["mom"][-1]["text"] == text and all(m["text"] != text for m in s.group)
