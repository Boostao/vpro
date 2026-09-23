-- VP08 Sample example; substitute validated project-family identifiers together.
-- UserSiteUnit is the documented successor to legacy AssignedSiteUnit.
WITH all_veg AS (
  SELECT PlotNumber, '1' AS MyLayer, Species, Cover1 AS Cover FROM Sample_Veg WHERE Cover1 IS NOT NULL
  UNION SELECT PlotNumber, '2', Species, Cover2 FROM Sample_Veg WHERE Cover2 IS NOT NULL
  UNION SELECT PlotNumber, '3', Species, Cover3 FROM Sample_Veg WHERE Cover3 IS NOT NULL
  UNION SELECT PlotNumber, '4', Species, Cover4 FROM Sample_Veg WHERE Cover4 IS NOT NULL
  UNION SELECT PlotNumber, '5', Species, Cover5 FROM Sample_Veg WHERE Cover5 IS NOT NULL
  UNION SELECT PlotNumber, '5a', Species, Cover5a FROM Sample_Veg WHERE Cover5a IS NOT NULL
  UNION SELECT PlotNumber, '5b', Species, Cover5b FROM Sample_Veg WHERE Cover5b IS NOT NULL
  UNION SELECT PlotNumber, '5c', Species, Cover5c FROM Sample_Veg WHERE Cover5c IS NOT NULL
  UNION SELECT PlotNumber, '6', Species, Cover6 FROM Sample_Veg WHERE Cover6 IS NOT NULL
  UNION SELECT PlotNumber, '7', Species, Cover7 FROM Sample_Veg WHERE Cover7 IS NOT NULL
  UNION SELECT PlotNumber, 'A', Species, TotalA FROM Sample_Veg WHERE TotalA IS NOT NULL
  UNION SELECT PlotNumber, 'B', Species, TotalB FROM Sample_Veg WHERE TotalB IS NOT NULL
)
SELECT e.PlotNumber, a.UserSiteUnit AS AssignedSiteUnit,
       v.MyLayer, v.Species, v.Cover
FROM Sample_Env AS e
JOIN all_veg AS v ON v.PlotNumber = e.PlotNumber
LEFT JOIN Sample_Admin AS a ON a.Plot = e.PlotNumber
ORDER BY v.MyLayer, e.PlotNumber, v.Species, v.Cover;
