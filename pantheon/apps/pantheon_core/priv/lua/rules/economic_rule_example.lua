-- PANTHEON Lua rule template: Economic Rule
-- Example government/economic policy hook: decide whether to intervene
-- in a region's market given its current price/stock snapshot.

function on_event(ctx)
  local market = ctx.market or {}
  local prices = market.prices or {}
  local threshold = ctx.threshold or 3.0

  for resource, price in pairs(prices) do
    if price > threshold then
      return { action = "release_reserves", resource = resource, price = price }
    end
  end

  return { action = "none" }
end
