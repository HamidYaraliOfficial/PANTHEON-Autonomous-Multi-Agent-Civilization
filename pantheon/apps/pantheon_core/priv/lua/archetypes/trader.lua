-- PANTHEON Lua archetype: Trader
-- Prioritises income/wealth and cross-region price differences while
-- still respecting basic survival needs.

local function most_urgent_need(needs)
  local worst_key, worst_val = nil, 2.0
  for k, v in pairs(needs) do
    if v < worst_val then
      worst_key, worst_val = k, v
    end
  end
  return worst_key, worst_val
end

function decide(agent)
  local needs = agent.needs or {}
  local personality = agent.personality or {}
  local worst_key, worst_val = most_urgent_need(needs)

  if worst_val < 0.2 then
    -- Even a trader has to eat and sleep eventually.
    return { type = "satisfy_need", need = worst_key }
  end

  if (needs.income or 0.5) < 0.6 or (personality.ambition or 0.5) > 0.6 then
    return { type = "seek_trade_opportunity", risk_tolerance = 1.0 - (personality.risk_aversion or 0.5) }
  end

  if (needs.social or 0.5) < 0.45 then
    return { type = "network_with_peers", need = "social" }
  end

  return { type = "satisfy_need", need = worst_key or "income" }
end
