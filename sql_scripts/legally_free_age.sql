IF OBJECT_ID('tempdb..##lf') IS NOT NULL
	DROP TABLE ##lf;

SELECT st
	,stfips
	,repdatyr AS ffy
	,recnumbr
	,latremdt
	,tprdate
	,dodfcdt
	,RANK() OVER (
		PARTITION BY recnumbr
		,repdatyr
		,latremdt ORDER BY DATEFROMPARTS(repdatyr, repdatmo, 30) DESC
		) AS rnk
	,DATEFROMPARTS(repdatyr - 1, 10, 1) AS start
	,CASE 
		WHEN ageatlatrem BETWEEN 0
				AND 4
			THEN 1
		WHEN ageatlatrem BETWEEN 5
				AND 9
			THEN 2
		WHEN ageatlatrem BETWEEN 10
				AND 14
			THEN 3
		WHEN ageatlatrem BETWEEN 15
				AND 17
			THEN 4
		END AS ageatlatrem
	,CASE 
		WHEN [dbo].[fnc_datediff_yrs](dob, DATEFROMPARTS(repdatyr - 1, 10, 1)) BETWEEN 0
				AND 4
			THEN 1
		WHEN [dbo].[fnc_datediff_yrs](dob, DATEFROMPARTS(repdatyr - 1, 10, 1)) BETWEEN 5
				AND 9
			THEN 2
		WHEN [dbo].[fnc_datediff_yrs](dob, DATEFROMPARTS(repdatyr - 1, 10, 1)) BETWEEN 10
				AND 14
			THEN 3
		WHEN [dbo].[fnc_datediff_yrs](dob, DATEFROMPARTS(repdatyr - 1, 10, 1)) BETWEEN 15
				AND 17
			THEN 4
		END AS age_at_start
	,NULL AS lf_at_start
	,NULL AS in_at_start
INTO ##lf
FROM [CA_ODS].[ndacan].[afcars_fc_6mo_2010_2016] AS a
LEFT JOIN CALENDAR_DIM AS cd ON a.tprdate = cd.CALENDAR_DATE
WHERE DATEDIFF(DAY, latremdt, ISNULL(dodfcdt, '9999-12-31')) > 7
	AND DATEDIFF(YEAR, dob, DATEFROMPARTS(repdatyr, repdatmo, 30)) < 18
	AND ageatlatrem BETWEEN 0
		AND 17
--AND st = 'WA'
ORDER BY tprdate
	,st

DELETE ##lf
WHERE rnk != 1

UPDATE ##lf
SET lf_at_start = IIF(tprdate < start
		AND ISNULL(dodfcdt, '9999-12-31') > start, 1, 0)
	,in_at_start = IIF(latremdt < start
		AND ISNULL(dodfcdt, '9999-12-31') > start, 1, 0)

IF OBJECT_ID('tempdb..##lf_los') IS NOT NULL
	DROP TABLE ##lf_los;

SELECT st
	,stfips
	,cd.FEDERAL_FISCAL_YYYY AS ffy
	,recnumbr
	,tprdate
	,dodfcdt
	,latremdt
	,RANK() OVER (
		PARTITION BY recnumbr
		,MONTH(latremdt)
		,YEAR(latremdt) ORDER BY DATEFROMPARTS(repdatyr, repdatmo, 30) DESC
		) AS rnk
	,DATEDIFF(DAY, tprdate, dodfcdt) AS dis
	,IIF(disreasn IN (
			1
			,2
			,3
			,5
			), 1, 0) AS perm_dis
	,NULL AS disyear
	,CASE 
		WHEN [dbo].[fnc_datediff_yrs](dob, tprdate) BETWEEN 0
				AND 4
			THEN 1
		WHEN [dbo].[fnc_datediff_yrs](dob, tprdate) BETWEEN 5
				AND 9
			THEN 2
		WHEN [dbo].[fnc_datediff_yrs](dob, tprdate) BETWEEN 10
				AND 14
			THEN 3
		WHEN [dbo].[fnc_datediff_yrs](dob, tprdate) BETWEEN 15
				AND 17
			THEN 4
		END AS age_at_lf
INTO ##lf_los
FROM [CA_ODS].[ndacan].[afcars_fc_6mo_2010_2016] AS a
LEFT JOIN CALENDAR_DIM AS cd ON a.tprdate = cd.CALENDAR_DATE
WHERE DATEDIFF(DAY, latremdt, ISNULL(dodfcdt, '9999-12-31')) > 7
	AND DATEDIFF(YEAR, dob, DATEFROMPARTS(repdatyr, repdatmo, 30)) < 18
	AND cd.FEDERAL_FISCAL_YYYY >= 2010
	AND tprdate IS NOT NULL
	AND ageatlatrem BETWEEN 0
		AND 17
--AND st = 'WA'
ORDER BY tprdate
	,st

DELETE ##lf_los
WHERE rnk != 1

UPDATE ##lf_los
SET disyear = IIF(perm_dis = 1
		AND dis < 365, 1, 0)

SELECT fd.ffy
	,fd.stfips
	,fd.st
	,0 AS age_at_start
	,0 AS age_at_lf
	,fd.legally_free_first_day
	,fd.total_kids_in_care_first_day
	,fd.per_leg_free_first_day
	,lf.became_legally_free
	,lf.exit_one_year
	,lf.per_exit_one_year
FROM (
	SELECT ffy
		,st
		,stfips
		,SUM(lf_at_start) AS legally_free_first_day
		,SUM(in_at_start) AS total_kids_in_care_first_day
		,SUM(lf_at_start) * 1.0 / SUM(in_at_start) AS per_leg_free_first_day
	FROM ##lf
	GROUP BY ffy
		,st
		,stfips
	) AS fd
LEFT JOIN (
	SELECT ffy
		,st
		,stfips
		,COUNT(*) AS became_legally_free
		,SUM(disyear) AS exit_one_year
		,SUM(disyear) * 1.0 / COUNT(*) AS per_exit_one_year
	FROM ##lf_los
	GROUP BY ffy
		,st
		,stfips
	) AS lf ON fd.ffy = lf.ffy
	AND fd.stfips = lf.stfips

UNION ALL

SELECT fd.ffy
	,fd.stfips
	,fd.st
	,fd.age_at_start
	,lf.age_at_lf
	,fd.legally_free_first_day
	,fd.total_kids_in_care_first_day
	,fd.per_leg_free_first_day
	,lf.became_legally_free
	,lf.exit_one_year
	,lf.per_exit_one_year
FROM (
	SELECT ffy
		,st
		,stfips
		,age_at_start
		,SUM(lf_at_start) AS legally_free_first_day
		,SUM(in_at_start) AS total_kids_in_care_first_day
		,IIF(SUM(in_at_start) = 0, 0, SUM(lf_at_start) * 1.0 / SUM(in_at_start)) AS per_leg_free_first_day
	FROM ##lf
	GROUP BY ffy
		,st
		,stfips
		,age_at_start
	) AS fd
LEFT JOIN (
	SELECT ffy
		,st
		,stfips
		,age_at_lf
		,COUNT(*) AS became_legally_free
		,SUM(disyear) AS exit_one_year
		,SUM(disyear) * 1.0 / COUNT(*) AS per_exit_one_year
	FROM ##lf_los
	GROUP BY ffy
		,st
		,stfips
		,age_at_lf
	) AS lf ON fd.ffy = lf.ffy
	AND fd.stfips = lf.stfips
	AND fd.age_at_start = lf.age_at_lf
WHERE fd.ffy BETWEEN 2010
		AND 2016
ORDER BY ffy
	,stfips
	,st
	,age_at_start
	,age_at_lf
