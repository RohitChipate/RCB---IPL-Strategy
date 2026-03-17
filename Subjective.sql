use ipl;

-- 1.How does the toss decision affect the result of the match? (which visualizations could be used to present your answer better) And is the impact limited to only specific venues?
SELECT v.Venue_Id, v.Venue_Name, 
       CASE WHEN m.Toss_Decide = 1 THEN 'Field' ELSE 'Bat' END AS Toss_Decide, 
       COUNT(*) AS Total_Matches,
       SUM(CASE WHEN m.Toss_Winner = m.Match_Winner THEN 1 ELSE 0 END) AS Toss_Winner_Wins, 
       SUM(CASE WHEN m.Toss_Winner != m.Match_Winner THEN 1 ELSE 0 END) AS Toss_Winner_Losses,
       ROUND((SUM(CASE WHEN m.Toss_Winner = m.Match_Winner THEN 1 ELSE 0 END) * 100.0) / COUNT(*), 2) AS Win_Percentage
FROM Matches m
JOIN Venue v ON m.Venue_Id = v.Venue_Id
GROUP BY v.Venue_Id, v.Venue_Name, m.Toss_Decide
ORDER BY v.Venue_Name, Toss_Decide;

-- 2.Suggest some of the players who would be best fit for the team?
#List of consistently performing batsmen
SELECT p.Player_Name, 
       SUM(b.Runs_Scored) AS Total_Runs, 
       COUNT(b.Ball_Id) AS Balls_Faced, 
       ROUND((SUM(b.Runs_Scored) / COUNT(b.Ball_Id)) * 100, 2) AS Strike_Rate, 
       ROUND(SUM(b.Runs_Scored) / COUNT(DISTINCT m.Match_Id), 2) AS Average_Runs
FROM Player p
JOIN Ball_by_Ball b ON p.Player_Id = b.Striker
JOIN Matches m ON b.Match_Id = m.Match_Id
WHERE m.Season_Id >= 4
GROUP BY  p.Player_Name

ORDER BY Total_Runs DESC, Strike_Rate DESC
LIMIT 10;


#List of consistent bowlers
SELECT p.Player_Name, 
       COUNT(w.Player_Out) AS Wickets_Taken, 
      ROUND(SUM(bb.Ball_Id) / COUNT(w.Player_Out),2) AS Strike_Rate, 
      
       ROUND(SUM(bb.Runs_Scored) / (SUM(bb.Ball_Id)/6),2) AS Economy_Rate
FROM Player p
JOIN Ball_by_Ball bb ON p.Player_Id = bb.Bowler
JOIN Matches m ON bb.Match_Id = m.Match_Id
 JOIN Wicket_Taken w 
ON bb.Match_Id = w.Match_Id AND bb.Over_Id = w.Over_Id AND bb.Innings_No = w.Innings_No AND bb.Ball_Id = w.Ball_Id
WHERE m.Season_Id >= 4
GROUP BY p.Player_Id, p.Player_Name
ORDER BY Wickets_Taken DESC, Economy_Rate ASC, Strike_Rate ASC
LIMIT 10;





-- 3.What are some of the parameters that should be focused on while selecting the players?
#Key parameters for selecting players

# A. Death over bowling performance
SELECT p.Player_Name, 
      SUM(CASE WHEN bb.Over_Id >= 16 AND bb.Over_Id <= 20  AND p.Player_Id IN (SELECT Bowler FROM ball_by_ball) THEN bb.Runs_Scored ELSE 0 END) AS Death_Over_Runs_Conceded
FROM Player p
JOIN ball_by_ball bb ON p.Player_Id = bb.Striker OR p.Player_Id = bb.Bowler

JOIN Matches m ON bb.Match_Id = m.Match_Id 
WHERE m.Season_Id >= 4
GROUP BY  p.Player_Name
HAVING COUNT(bb.Ball_Id) > 100 AND Death_Over_Runs_Conceded != 0
ORDER BY Death_Over_Runs_Conceded ASC
LIMIT 10;


# B. Batting performance accross different venues



SELECT p.Player_Name, 
       v.Venue_Id, v.Venue_Name, 
       SUM(bb.Runs_Scored) AS Total_Runs, 
       COUNT(bb.Ball_Id) AS Balls_Faced, 
       ROUND(SUM(bb.Runs_Scored) / COUNT(bb.Ball_Id), 2) * 100 AS Strike_Rate
FROM Player p
JOIN Ball_by_Ball bb ON p.Player_Id = bb.Striker
JOIN Matches m ON bb.Match_Id = m.Match_Id
JOIN Venue v ON m.Venue_Id = v.Venue_Id
JOIN Ball_by_Ball bb2 
ON bb.Match_Id = bb2.Match_Id 
AND bb.Over_Id = bb2.Over_Id 
AND bb.Ball_Id = bb2.Ball_Id 
AND bb.Innings_No = bb2.Innings_No
GROUP BY p.Player_Name, v.Venue_Id, v.Venue_Name
ORDER BY Total_Runs DESC, Strike_Rate DESC
LIMIT 10;





-- Q4. Which players offer versatility in their skills and can contribute effectively with both bat and ball? (can you visualize the data for the same)
#We can find all-rounder performance for all players

WITH All_Rounder_Performance AS (
    SELECT
        p.Player_Id,
        p.Player_Name,

        /* Batting contribution */
        SUM(CASE 
                WHEN bbb.Striker = p.Player_Id 
                THEN bbb.Runs_Scored 
                ELSE 0 
            END) AS Total_Runs,

        COUNT(DISTINCT CASE 
                WHEN bbb.Striker = p.Player_Id 
                THEN m.Match_Id 
            END) AS Batting_Matches,

        /* Bowling contribution */
        COUNT(CASE 
                WHEN bbb.Bowler = p.Player_Id 
                     AND wt.Player_Out IS NOT NULL 
                THEN 1 
            END) AS Wickets_Taken

    FROM Player p
    JOIN Ball_by_Ball bbb
        ON p.Player_Id IN (bbb.Striker, bbb.Bowler)
    JOIN Matches m
        ON bbb.Match_Id = m.Match_Id
    LEFT JOIN Wicket_Taken wt
        ON bbb.Match_Id = wt.Match_Id
        AND bbb.Over_Id = wt.Over_Id
        AND bbb.Ball_Id = wt.Ball_Id
        AND bbb.Innings_No = wt.Innings_No

    GROUP BY p.Player_Id, p.Player_Name
)

SELECT
    Player_Name,
    Total_Runs,
    Wickets_Taken,
    ROUND(Total_Runs * 1.0 / NULLIF(Batting_Matches, 0), 2) AS Avg_Runs_Per_Match
FROM All_Rounder_Performance
WHERE Total_Runs > 400
  AND Wickets_Taken > 20
ORDER BY Total_Runs DESC, Wickets_Taken DESC;


-- Q5.	Are there players whose presence positively influences the morale and performance of the team? (justify your answer using visualisation)



WITH cte AS (
    -- Extract relevant match details for the 2015 and 2016 seasons
    SELECT bbb.Striker, m.Season_Id, s.Season_Year, 
           bbb.Match_Id, bbb.Over_Id, bbb.Ball_Id, 
           bbb.Innings_No, bbb.Runs_Scored
    FROM ball_by_ball bbb
    JOIN matches m 
        ON bbb.Match_Id = m.Match_Id
    JOIN season s 
        ON m.Season_Id = s.Season_Id
    WHERE s.Season_Year IN (2015, 2016)
),

cte2 AS (
    -- Calculate total runs per player
    SELECT Striker, SUM(Runs_Scored) AS Total_Runs
    FROM cte 
    GROUP BY Striker
),

cte3 AS (
    -- Calculate runs from boundaries (4s and 6s) per player
    SELECT Striker, SUM(Runs_Scored) AS Runs_In_Boundaries
    FROM cte
    WHERE Runs_Scored IN (4, 6)
    GROUP BY Striker
)

-- Final output with boundary percentage calculation
SELECT c2.Striker AS Player_Id, p.Player_Name, 
       c2.Total_Runs, c3.Runs_In_Boundaries, 
       ROUND((c3.Runs_In_Boundaries * 100.0 / c2.Total_Runs), 2) AS Boundary_Percentage 
FROM cte2 c2
JOIN cte3 c3 ON c2.Striker = c3.Striker
JOIN player p ON c2.Striker = p.Player_Id
WHERE c2.Total_Runs >= 100
ORDER BY Boundary_Percentage DESC;


-- 6.What would you suggest to RCB before going to mega auction?  

# Identify good all-rounders for better team combinations.
WITH batting_performance AS (
    SELECT p.Player_Id, p.Player_Name,
           SUM(bb.Runs_Scored) AS Total_Runs,
           COUNT(bb.Ball_Id) AS Balls_Faced,
           ROUND((SUM(bb.Runs_Scored) / COUNT(bb.Ball_Id)) * 100, 2) AS Batting_Strike_Rate
    FROM player p
    JOIN ball_by_ball bb 
        ON p.Player_Id = bb.Striker
    JOIN matches m 
        ON bb.Match_Id = m.Match_Id
    JOIN ball_by_ball b  
        ON bb.Match_Id = b.Match_Id 
       AND bb.Over_Id = b.Over_Id 
       AND bb.Ball_Id = b.Ball_Id 
       AND bb.Innings_No = b.Innings_No
    WHERE bb.Runs_Scored IS NOT NULL
    GROUP BY p.Player_Id, p.Player_Name
),

  bowling_performance AS (
    SELECT p.Player_Id, p.Player_Name, 
           COUNT(w.Player_Out) AS Total_Wickets,
           ROUND(SUM(bb.Runs_Scored) / (COUNT(bb.Ball_Id) / 6.0), 2) AS Economy_Rate 
    FROM player p
    JOIN ball_by_ball bb ON p.Player_Id = bb.Bowler
    LEFT JOIN wicket_taken w 
        ON bb.Match_Id = w.Match_Id 
        AND bb.Over_Id = w.Over_Id 
        AND bb.Ball_Id = w.Ball_Id 
        AND bb.Innings_No = w.Innings_No
    JOIN ball_by_ball bs 
        ON bs.Match_Id = bb.Match_Id
        AND bs.Over_Id = bb.Over_Id 
        AND bs.Ball_Id = bb.Ball_Id 
        AND bs.Innings_No = bb.Innings_No
    GROUP BY p.Player_Id, p.Player_Name
    HAVING COUNT(bb.Ball_Id) > 100
)

SELECT DISTINCT bp.Player_Id, bp.Player_Name, 
       bp.Total_Runs, bp.Batting_Strike_Rate, bp.Balls_Faced,
       bw.Total_Wickets, bw.Economy_Rate
FROM batting_performance bp
JOIN bowling_performance bw ON bp.Player_Id = bw.Player_Id
JOIN player_match pm ON bp.Player_Id = pm.Player_Id
WHERE pm.Role_Id NOT IN (SELECT Role_Id FROM rolee WHERE Role_Desc IN ("Keeper","CaptainKeeper"))
AND bp.Balls_Faced > 100
ORDER BY bp.Batting_Strike_Rate DESC, bw.Economy_Rate ASC
LIMIT 10;

-- 7.What do you think could be the factors contributing to the high-scoring matches and the impact on viewership and team strategies?

/* Powerplay and Death Over Utilization: In high-scoring matches, teams aim to maximize the powerplay (overs 1-6) and death overs (Overs 16-20) by scoring aggressively. */
SELECT 
    t.Team_Name,
    SUM(CASE
        WHEN bb.Over_Id BETWEEN 1 AND 6 THEN bb.Runs_Scored
        ELSE 0
    END) AS Powerplay_Runs,
    SUM(CASE
        WHEN bb.Over_Id BETWEEN 16 AND 20 THEN bb.Runs_Scored
        ELSE 0
    END) AS Death_Over_Runs
FROM
    team t
        JOIN
    matches m ON t.Team_Id = m.Team_1
        OR t.Team_Id = m.Team_2
        JOIN
    ball_by_ball bb ON m.Match_Id = bb.Match_Id
GROUP BY t.Team_Name
ORDER BY Powerplay_Runs DESC , Death_Over_Runs DESC;


/* High Scoring Venues: Some venues favour the batsmen more then others, venues play a significant role in a high-scoring match */
SELECT v.Venue_Name, 
       AVG(match_runs.Total_Runs) AS Avg_Runs_Per_Match,
       COUNT(m.Match_Id) AS Total_Matches
FROM venue v
JOIN matches m ON v.Venue_Id = m.Venue_Id
JOIN (
    SELECT bb.Match_Id, SUM(bb.Runs_Scored) AS Total_Runs
    FROM ball_by_ball bb
    GROUP BY bb.Match_Id
) AS match_runs ON m.Match_Id = match_runs.Match_Id
GROUP BY v.Venue_Name
ORDER BY Total_Matches DESC, Avg_Runs_Per_Match DESC
LIMIT 10;

-- 8.Analyze the impact of home ground advantage on team performance and identify strategies to maximize this advantage for RCB.

SELECT 
    CASE 
        WHEN v.Venue_Name LIKE '%Chinnaswamy%' OR v.Venue_Name LIKE '%Bangalore%' 
        THEN 'Home (Chinnaswamy)'
        ELSE 'Away'
    END as Venue_Type,
    COUNT(*) as Total_Matches,
    SUM(CASE 
        WHEN m.Match_Winner = t.Team_Id THEN 1 
        ELSE 0 
    END) as Wins,
    SUM(CASE 
        WHEN m.Match_Winner != t.Team_Id OR m.Match_Winner IS NULL THEN 1 
        ELSE 0 
    END) as Losses,
    ROUND(SUM(CASE 
        WHEN m.Match_Winner = t.Team_Id THEN 1 
        ELSE 0 
    END) * 100.0 / COUNT(*), 2) as Win_Percentage,
    ROUND(AVG(CASE 
        WHEN m.Win_Type = 1 AND m.Match_Winner = t.Team_Id 
        THEN m.Win_Margin 
    END), 2) as Avg_Run_Margin_When_Won,
    ROUND(AVG(CASE 
        WHEN m.Win_Type = 2 AND m.Match_Winner = t.Team_Id 
        THEN m.Win_Margin 
    END), 2) as Avg_Wicket_Margin_When_Won
FROM Matches m
JOIN Team t ON (m.Team_1 = t.Team_Id OR m.Team_2 = t.Team_Id)
JOIN Venue v ON m.Venue_Id = v.Venue_Id
WHERE t.Team_Name LIKE '%Royal Challengers%' 
    OR t.Team_Name LIKE '%Bangalore%'
GROUP BY Venue_Type
ORDER BY Win_Percentage DESC;

-- 9.Come up with a visual and analytical analysis with the RCB past seasons performance and potential reasons for them not winning a trophy.
--  1.OVERALL WIN/LOSS RECORD BY SEASON

SELECT 
    s.Season_Year,
    COUNT(CASE WHEN m.Match_Winner = t.Team_Id THEN 1 END) AS Wins,
    COUNT(CASE WHEN m.Match_Winner != t.Team_Id AND m.Match_Winner IS NOT NULL THEN 1 END) AS Losses,
    COUNT(*) AS Total_Matches,
    ROUND(COUNT(CASE WHEN m.Match_Winner = t.Team_Id THEN 1 END) * 100.0 / COUNT(*), 2) AS Win_Percentage
FROM Matches m
JOIN Team t ON (m.Team_1 = t.Team_Id OR m.Team_2 = t.Team_Id)
JOIN Season s ON m.Season_Id = s.Season_Id
WHERE t.Team_Name LIKE '%Royal Challengers%'
GROUP BY s.Season_Year
ORDER BY s.Season_Year;


-- 2. PLAYOFF APPEARANCES AND FINALS

SELECT 
    s.Season_Year,
    COUNT(CASE WHEN m.Match_Winner = t.Team_Id THEN 1 END) AS Wins,
    CASE 
        WHEN COUNT(CASE WHEN m.Match_Winner = t.Team_Id THEN 1 END) >= 8 THEN 'Likely Playoff'
        ELSE 'Missed Playoff'
    END AS Playoff_Status
FROM Matches m
JOIN Team t ON (m.Team_1 = t.Team_Id OR m.Team_2 = t.Team_Id)
JOIN Season s ON m.Season_Id = s.Season_Id
WHERE t.Team_Name LIKE '%Royal Challengers%'
GROUP BY s.Season_Year
ORDER BY s.Season_Year;

-- 3. TOSS WIN vs MATCH WIN CORRELATION

SELECT 
    s.Season_Year,
    COUNT(CASE WHEN m.Toss_Winner = t.Team_Id THEN 1 END) AS Tosses_Won,
    COUNT(CASE WHEN m.Toss_Winner = t.Team_Id AND m.Match_Winner = t.Team_Id THEN 1 END) AS Matches_Won_After_Winning_Toss,
    ROUND(COUNT(CASE WHEN m.Toss_Winner = t.Team_Id AND m.Match_Winner = t.Team_Id THEN 1 END) * 100.0 / 
          NULLIF(COUNT(CASE WHEN m.Toss_Winner = t.Team_Id THEN 1 END), 0), 2) AS Toss_Win_Conversion_Rate
FROM Matches m
JOIN Team t ON (m.Team_1 = t.Team_Id OR m.Team_2 = t.Team_Id)
JOIN Season s ON m.Season_Id = s.Season_Id
WHERE t.Team_Name LIKE '%Royal Challengers%'
GROUP BY s.Season_Year
ORDER BY s.Season_Year;

-- 4. WIN MARGIN ANALYSIS (Strength of Wins)

SELECT 
    s.Season_Year,
    wb.Win_Type,
    AVG(m.Win_Margin) AS Avg_Win_Margin,
    MIN(m.Win_Margin) AS Min_Win_Margin,
    MAX(m.Win_Margin) AS Max_Win_Margin,
    COUNT(*) AS Number_of_Wins
FROM Matches m
JOIN Team t ON m.Match_Winner = t.Team_Id
JOIN Season s ON m.Season_Id = s.Season_Id
JOIN Win_By wb ON m.Win_Type = wb.Win_Id
WHERE t.Team_Name LIKE '%Royal Challengers%'
GROUP BY s.Season_Year, wb.Win_Type
ORDER BY s.Season_Year, wb.Win_Type;

-- 5. BATTING FIRST vs CHASING SUCCESS RATE

SELECT 
    s.Season_Year,
    COUNT(CASE WHEN td.Toss_Name = 'bat' AND m.Toss_Winner = t.Team_Id AND m.Match_Winner = t.Team_Id THEN 1 END) AS Won_Batting_First,
    COUNT(CASE WHEN td.Toss_Name = 'field' AND m.Toss_Winner = t.Team_Id AND m.Match_Winner = t.Team_Id THEN 1 END) AS Won_Chasing,
    COUNT(CASE WHEN td.Toss_Name = 'bat' AND m.Toss_Winner = t.Team_Id AND m.Match_Winner != t.Team_Id THEN 1 END) AS Lost_Batting_First,
    COUNT(CASE WHEN td.Toss_Name = 'field' AND m.Toss_Winner = t.Team_Id AND m.Match_Winner != t.Team_Id THEN 1 END) AS Lost_Chasing
FROM Matches m
JOIN Team t ON (m.Team_1 = t.Team_Id OR m.Team_2 = t.Team_Id)
JOIN Season s ON m.Season_Id = s.Season_Id
JOIN Toss_Decision td ON m.Toss_Decide = td.Toss_Id
WHERE t.Team_Name LIKE '%Royal Challengers%' AND m.Toss_Winner = t.Team_Id
GROUP BY s.Season_Year
ORDER BY s.Season_Year; 
