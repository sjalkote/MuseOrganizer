"""Deterministic finance math. Spark explains these numbers; it never produces them.

Rates are fractions (0.065 = 6.5% APR). Money is plain floats: these are estimates, not a ledger.
"""


def _check(principal, apr, months):
    if principal < 0 or apr < 0 or months <= 0:
        raise ValueError("need principal >= 0, apr >= 0, months > 0")


def monthly_payment(principal, apr, months):
    """Standard amortized loan payment."""
    _check(principal, apr, months)
    r = apr / 12
    return principal / months if r == 0 else principal * r / (1 - (1 + r) ** -months)


def balance_after(principal, apr, months, k):
    """Loan balance remaining after k payments."""
    pmt = monthly_payment(principal, apr, months)
    k = min(k, months)
    r = apr / 12
    if r == 0:
        return principal - pmt * k
    g = (1 + r) ** k
    return max(0.0, principal * g - pmt * (g - 1) / r)


def apr_from_money_factor(mf):
    """Leases quote a 'money factor'; multiply by 2400 for APR in percent, 24 for a fraction."""
    return mf * 24


def lease_payment(price, residual_pct, money_factor, months, tax_pct=0.0, fees=0.0, cap_reduction=0.0):
    """Monthly lease payment = depreciation fee + rent charge, plus sales tax on the payment."""
    if price <= 0 or months <= 0 or not 0 < residual_pct < 1 or money_factor < 0:
        raise ValueError("bad lease inputs")
    cap = price + fees - cap_reduction
    residual = price * residual_pct
    depreciation = (cap - residual) / months
    rent = (cap + residual) * money_factor
    return (depreciation + rent) * (1 + tax_pct)


def compare(price, *, apr, months, down_pct, tax_pct, lease_months, residual_pct, money_factor, lease_fees=0.0):
    """Cash vs finance vs lease over the lease term, so all three cover the same months.

    net_cost = what you paid during the term minus the equity you hold at the end of it.
    ponytail: the car's value at lease end is estimated by the lease residual; swap in market data if available.
    """
    h = lease_months
    out_the_door = price * (1 + tax_pct)
    value_at_end = price * residual_pct

    down = out_the_door * down_pct
    loan = out_the_door - down
    pmt = monthly_payment(loan, apr, months)
    paid_months = min(h, months)
    balance = balance_after(loan, apr, months, paid_months)

    lease_pmt = lease_payment(price, residual_pct, money_factor, lease_months, tax_pct, lease_fees)
    lease_rent = (price + lease_fees + value_at_end) * money_factor * lease_months

    plans = {
        "cash": {"upfront": out_the_door, "monthly": 0, "total_paid": out_the_door,
                 "interest": 0, "equity": value_at_end},
        "finance": {"upfront": down, "monthly": pmt, "total_paid": down + pmt * paid_months,
                    "interest": pmt * paid_months - (loan - balance), "equity": value_at_end - balance,
                    "loan_total_interest": pmt * months - loan, "loan_months": months},
        "lease": {"upfront": lease_pmt, "monthly": lease_pmt, "total_paid": lease_pmt * lease_months,
                  "interest": lease_rent, "equity": 0, "apr_equivalent": apr_from_money_factor(money_factor)},
    }
    for p in plans.values():
        p["net_cost"] = p["total_paid"] - p["equity"]
        for k, v in p.items():
            if k != "apr_equivalent":
                p[k] = round(v)
    best = min(plans, key=lambda k: plans[k]["net_cost"])
    return {"months": h, "best": best, **plans}


if __name__ == "__main__":
    import json
    print(json.dumps(compare(32850, apr=0.065, months=60, down_pct=0.1, tax_pct=0.0625,
                             lease_months=36, residual_pct=0.6, money_factor=0.0025, lease_fees=650), indent=2))
