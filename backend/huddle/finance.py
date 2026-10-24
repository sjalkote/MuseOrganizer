"""Deterministic finance math. Spark explains these numbers; it never produces them."""


def monthly_payment(principal, apr, months):
    r = apr / 12
    return principal / months if r == 0 else principal * r / (1 - (1 + r) ** -months)
