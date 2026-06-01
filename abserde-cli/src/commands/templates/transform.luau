--!strict

-- Transformations are keyed by the version they migrate TO.
-- Each function receives data from the previous version and must return the transformed data.
-- Versions are applied in ascending order, so any gaps are handled automatically.

return {
	[2] = function(data: any): any
		-- Migrate Level: square the old value as an example transformation.
		data.Level = data.Level * data.Level
		return data
	end,
}
