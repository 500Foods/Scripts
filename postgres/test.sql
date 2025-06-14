SELECT
  key_idx,
  value_txt,
  (collection ->> 'Name')::Text AS name,
  (collection ->> 'Model')::Text AS model,
  (collection ->> 'Engine')::Text AS engine,
  (collection ->> 'Pinged')::Text AS pinged,
  (collection ->> 'Ponged')::Text AS ponged
FROM
  app.lookups
WHERE
  (lookup_id = 38)
  AND (status_lua_1 = 1)
  AND (
    (valid_after IS NULL)
    OR (valid_after <= CURRENT_TIMESTAMP)
  )
  AND (
    (valid_until IS NULL)
    OR (valid_until >= CURRENT_TIMESTAMP)
  )
  AND (
    -- Never succeeded: Ponged IS NULL 
    collection ->> 'Ponged' IS NULL

    OR

    -- Last ping failed (Ponged < Pinged)
    (collection ->> 'Ponged')::timestamptz
      < (collection ->> 'Pinged')::timestamptz

    OR

    -- Healthy but “stale”: last pong > 1h ago 
    (collection ->> 'Ponged')::timestamptz
      < NOW() - INTERVAL '1 hour'

    OR

    -- Just failed recently, yet had a successful pong <1h ago:
    -- Ponged ≥ 1h‐ago AND Pinged < 1 day‐ago 
    (
      (collection ->> 'Ponged')::timestamptz >= NOW() - INTERVAL '1 hour'
      AND
      (collection ->> 'Pinged')::timestamptz  > NOW() - INTERVAL '1 day'
    )
  )
ORDER BY
  collection -> 'Name'
