# Runbook: commerce_db Schema Migration (tonight)

## Goal
Add a `loyalty_tier` column to `customers` in `commerce_db`, backfilled from the
`customer_blob` JSON payload each row already carries, then cut traffic over to
the new column.

## Steps

1. Take a snapshot of `commerce_db` (standard nightly snapshot job, already
   scheduled).
2. Run `migrate_add_loyalty_tier.sql` against `commerce_db` to add the new
   nullable `loyalty_tier` column.
3. Run `backfill_loyalty_tier.py`, which reads each row's `customer_blob` JSON
   column, extracts `tier`, and writes it into the new `loyalty_tier` column.
4. Deploy the app version that reads `loyalty_tier` directly instead of parsing
   `customer_blob` on every request.
5. Platform team flips the `USE_LOYALTY_TIER_COLUMN` feature flag to `true`.
6. Someone should send a note to marketing that the new tier column is live so
   they can start using it in campaign targeting.

## Notes

- `backfill_loyalty_tier.py` assumes every row's `customer_blob` is valid JSON
  with a `tier` key present.
- This runs against production `commerce_db` during the nightly maintenance
  window.
