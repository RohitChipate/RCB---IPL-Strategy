use ipl;



-- 1.List the different dtypes of columns in table “ball_by_ball” (using information schema)
SELECT COLUMN_NAME, DATA_TYPE FROM information_schema.columns
WHERE table_name = 'Ball_by_Ball' AND table_schema = "ipl";


-- 2.What is the total number of run scored in 1st season by RCB? (bonus : also include the extra runs using the extra runs table)
WITH extra_run_data AS (

SELECT

Team_Batting AS team_Id,

SUM(e.Extra_Runs) as total_extra

FROM ball_by_ball b

JOIN extra_runs e ON e.Match_Id = b.Match_Id AND e.Innings_No = b.Innings_No AND e.Over_Id = b.Over_Id AND e.Ball_Id = b.Ball_Id

WHERE Team_Batting = 2

AND b.Match_Id IN(

SELECT distinct Match_Id FROM matches WHERE Season_Id = ( SELECT MIN(Season_Id) as first_season FROM Matches WHERE Team_1 = 2 OR Team_2 = 2))

),

run_scored_data AS (

SELECT

Team_Batting AS team_Id,

SUM(b.Runs_Scored) AS total_score

FROM ball_by_ball b

JOIN matches m ON m.Match_Id = b.Match_Id

WHERE Team_Batting = 2 AND (Team_1 = 2 OR Team_2 = 2) AND m.Season_Id = ( SELECT MIN(Season_Id) as first_season FROM Matches WHERE Team_1 = 2 OR Team_2 = 2)

)

SELECT

(total_score + total_extra) AS total_runs

FROM run_scored_data s

JOIN extra_run_data e ON e.team_Id = s.team_Id;





-- 3. How many players were more than the age of 25 during season 2014?
SELECT COUNT(DISTINCT p.Player_Id) AS Players_Age_Above_25
FROM Player p
JOIN Player_Match pm ON p.Player_Id = pm.Player_Id
JOIN Matches m ON pm.Match_Id = m.Match_Id
JOIN Season s ON m.Season_Id = s.Season_Id
WHERE s.Season_Year = 2014
AND TIMESTAMPDIFF(YEAR, p.DOB, '2014-12-31') > 25;

-- 4..How many matches did RCB win in 2013? 
SELECT COUNT(*) AS Matches_Won
FROM Matches m
JOIN Season s ON m.Season_Id = s.Season_Id
JOIN Team t ON m.Match_Winner = t.Team_Id
WHERE s.Season_Year = 2013
AND t.Team_Name = 'Royal Challengers Bangalore'
AND m.Match_Winner IS NOT NULL;


-- 5.List the top 10 players according to their strike rate in the last 4 seasons
WITH Last_4_Seasons AS (
    SELECT Season_Year FROM Season ORDER BY Season_Year DESC LIMIT 4
),
Striker_Rate AS (
    SELECT 
        B.Striker, 
        ROUND((SUM(B.Runs_Scored) / NULLIF(COUNT(B.Ball_Id), 0)) * 100, 2) AS Strike_Rate
    FROM Ball_by_Ball B
    JOIN Matches M ON B.Match_Id = M.Match_Id
    JOIN Season S ON M.Season_Id = S.Season_Id
    JOIN Last_4_Seasons L4S ON S.Season_Year = L4S.Season_Year
    GROUP BY B.Striker
    HAVING COUNT(B.Ball_Id) > 100
)
SELECT 
    RANK() OVER (ORDER BY SR.Strike_Rate DESC) AS Ranking,
    P.Player_Name, 
    SR.Strike_Rate
FROM Striker_Rate SR
JOIN Player P ON SR.Striker = P.Player_Id
ORDER BY SR.Strike_Rate DESC
LIMIT 10;

-- 6.What are the average runs scored by each batsman considering all the seasons?
SELECT 
    p.Player_Name,
    SUM(COALESCE(b.Runs_Scored, 0)) AS Total_Runs,
    COUNT(DISTINCT CONCAT(b.Match_Id, '-', b.Innings_No)) AS Innings_Played,
    ROUND(SUM(COALESCE(b.Runs_Scored, 0)) / NULLIF(COUNT(DISTINCT CONCAT(b.Match_Id, '-', b.Innings_No)), 0), 2) AS Avg_Runs
FROM Ball_by_Ball b
JOIN Player p ON b.Striker = p.Player_Id
GROUP BY p.Player_Name
ORDER BY Avg_Runs DESC;


-- 7.What are the average wickets taken by each bowler considering all the seasons?
WITH wickets_count_per_player_per_season AS
(SELECT  b.Bowler, m.Season_Id,  COUNT(w.Player_Out) AS wickets_taken
FROM ball_by_ball b
JOIN wicket_taken w 
ON b.Match_Id = w.Match_Id AND
b.Over_Id = w.Over_Id AND
b.Ball_Id = w.Ball_Id AND
b.Innings_No = w.Innings_No
JOIN Matches m 
ON m.Match_Id = w.Match_Id
GROUP BY 1,2
ORDER BY b.Bowler ASC, m.Season_Id ASC),
avg_per_season AS (
SELECT *, AVG(wickets_taken) OVER(PARTITION BY Bowler) AS avg_wicket_per_bowler
FROM wickets_count_per_player_per_season)

SELECT DISTINCT p.Player_Name,ROUND(a.avg_wicket_per_bowler,2) AS Avg_wicket
FROM avg_per_season a
JOIN Player p
ON p.Player_Id = a.Bowler
WHERE a.avg_wicket_per_bowler > 0
ORDER BY Avg_wicket DESC;


-- 8.List all the players who have average runs scored greater than the overall average and who have taken wickets greater than the overall average
WITH Overall_Batting_Avg AS (
    SELECT AVG(player_avg) as overall_avg
    FROM (
        SELECT SUM(Runs_Scored) * 1.0 / COUNT(DISTINCT CONCAT(Match_Id, '-', Innings_No)) as player_avg
        FROM Ball_by_Ball
        GROUP BY Striker
    ) as batting_averages
),
Overall_Wickets_Avg AS (
    SELECT AVG(bowler_avg) as overall_avg
    FROM (
        SELECT COUNT(w.Player_Out) * 1.0 / COUNT(DISTINCT b.Match_Id) as bowler_avg
        FROM Ball_by_Ball b
        LEFT JOIN Wicket_Taken w ON b.Match_Id = w.Match_Id 
                                 AND b.Over_Id = w.Over_Id 
                                 AND b.Ball_Id = w.Ball_Id 
                                 AND b.Innings_No = w.Innings_No
        GROUP BY b.Bowler
        HAVING COUNT(w.Player_Out) > 0
    ) as bowling_averages
),
Batting_Stats AS (
    SELECT 
        Striker as Player_Id,
        SUM(Runs_Scored) as Total_Runs,
        COUNT(DISTINCT CONCAT(Match_Id, '-', Innings_No)) as Innings,
        ROUND(SUM(Runs_Scored) * 1.0 / COUNT(DISTINCT CONCAT(Match_Id, '-', Innings_No)), 2) as Avg_Runs
    FROM Ball_by_Ball
    GROUP BY Striker
),
Bowling_Stats AS (
    SELECT 
        b.Bowler as Player_Id,
        COUNT(w.Player_Out) as Total_Wickets,
        COUNT(DISTINCT b.Match_Id) as Matches,
        ROUND(COUNT(w.Player_Out) * 1.0 / COUNT(DISTINCT b.Match_Id), 2) as Avg_Wickets
    FROM Ball_by_Ball b
    LEFT JOIN Wicket_Taken w ON b.Match_Id = w.Match_Id 
                             AND b.Over_Id = w.Over_Id 
                             AND b.Ball_Id = w.Ball_Id 
                             AND b.Innings_No = w.Innings_No
    GROUP BY b.Bowler
    HAVING Total_Wickets > 0
)
SELECT 
    p.Player_Name,
    bat.Total_Runs,
    bat.Innings,
    bat.Avg_Runs,
    bowl.Total_Wickets,
    bowl.Matches,
    bowl.Avg_Wickets,
    (SELECT overall_avg FROM Overall_Batting_Avg) as Overall_Batting_Avg,
    (SELECT overall_avg FROM Overall_Wickets_Avg) as Overall_Wickets_Avg
FROM Player p
INNER JOIN Batting_Stats bat ON p.Player_Id = bat.Player_Id
INNER JOIN Bowling_Stats bowl ON p.Player_Id = bowl.Player_Id
WHERE bat.Avg_Runs > (SELECT overall_avg FROM Overall_Batting_Avg)
  AND bowl.Avg_Wickets > (SELECT overall_avg FROM Overall_Wickets_Avg)
ORDER BY bat.Avg_Runs DESC, bowl.Avg_Wickets DESC;


-- 9.Create a table rcb_record table that shows the wins and losses of RCB in an individual venue.
DROP TABLE IF EXISTS rcb_record_table;

CREATE TABLE IF NOT EXISTS rcb_record_table AS 
WITH rcb_record AS 
(SELECT m.Venue_Id, v.Venue_Name,
SUM(CASE WHEN Match_Winner = 2 THEN 1 ELSE 0 END) AS Win_record,
SUM(CASE WHEN Match_Winner != 2 THEN 1 ELSE 0 END) AS Loss_record
FROM matches m
JOIN venue v 
ON m.Venue_Id = v.Venue_Id
WHERE (Team_1 = 2 OR Team_2 = 2) AND m.Outcome_type != 2
GROUP BY 1,2)

SELECT *, Win_record + Loss_record AS Total_Played,
ROUND((Win_record/(Win_record + Loss_record))*100,2) AS Win_percentage, ROUND((Loss_record/(Win_record + Loss_record))*100,2) AS Loss_percentage
FROM rcb_record
ORDER BY Venue_Id;

SELECT Venue_Name,Win_record,Loss_record,Total_Played,Win_percentage,Loss_percentage FROM rcb_record_table;

-- 10.What is the impact of bowling style on wickets taken?
WITH no_of_wicket_per_bowler AS (
SELECT bb.bowler,  COUNT(w.Player_Out) AS no_of_wickets
FROM wicket_taken w 
JOIN ball_by_ball bb 
ON w.Match_Id = bb.Match_Id 
    AND w.Over_Id = bb.Over_Id 
    AND w.Ball_Id = bb.Ball_Id 
    AND w.Innings_No = bb.Innings_No
GROUP BY bb.Bowler),
bowler_skill_wicket AS
(SELECT  n.bowler, st.Bowling_skill, no_of_wickets 
FROM no_of_wicket_per_bowler n 
JOIN player p
ON n.bowler = p.Player_Id
JOIN bowling_style st
ON st.Bowling_Id = p.Bowling_skill
ORDER BY no_of_wickets DESC)
SELECT Bowling_skill AS Bowling_Style, SUM(no_of_wickets) AS total_wickets_taken
FROM bowler_skill_wicket
GROUP BY Bowling_skill
ORDER BY total_wickets_taken DESC;

-- 11.Write the SQL query to provide a status of whether the performance of the team is better than the previous year's performance on the basis of the number of runs scored by the team in the season and the number of wickets taken 
WITH Team_Season_Stats AS (
    -- Runs scored per team per season
    SELECT 
        t.Team_Id,
        t.Team_Name,
        s.Season_Year,
        SUM(b.Runs_Scored) AS Total_Runs,
        COUNT(DISTINCT w.Player_Out) AS Total_Wickets
    FROM Team t
    JOIN Matches m 
        ON t.Team_Id = m.Team_1 OR t.Team_Id = m.Team_2
    JOIN Season s 
        ON m.Season_Id = s.Season_Id
    LEFT JOIN Ball_by_Ball b 
        ON m.Match_Id = b.Match_Id 
        AND b.Team_Batting = t.Team_Id
    LEFT JOIN Wicket_Taken w 
        ON b.Match_Id = w.Match_Id
        AND b.Over_Id = w.Over_Id
        AND b.Ball_Id = w.Ball_Id
        AND b.Innings_No = w.Innings_No
    GROUP BY 
        t.Team_Id, t.Team_Name, s.Season_Year
),

Comparison AS (
    SELECT
        Team_Id,
        Team_Name,
        Season_Year,
        Total_Runs,
        Total_Wickets,

        LAG(Total_Runs) OVER 
            (PARTITION BY Team_Id ORDER BY Season_Year) AS Prev_Runs,

        LAG(Total_Wickets) OVER 
            (PARTITION BY Team_Id ORDER BY Season_Year) AS Prev_Wickets

    FROM Team_Season_Stats
)

SELECT
    Team_Name,
    Season_Year,
    Total_Runs,
    Total_Wickets,

    CASE
        WHEN Prev_Runs IS NULL THEN 'First Season'
        WHEN Total_Runs > Prev_Runs 
             AND Total_Wickets > Prev_Wickets
             THEN 'Better than Previous Year'
        ELSE 'Not Better than Previous Year'
    END AS Performance_Status

FROM Comparison
ORDER BY Team_Name, Season_Year;


-- Q12.	Can you derive more KPIs for the team strategy if possible?
 -- KPI #1 Boundary %
SELECT pm.Player_Id, p.Player_Name,
       ROUND((SUM(CASE WHEN b.Runs_Scored = 4 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS Four_Percentage,
       ROUND((SUM(CASE WHEN b.Runs_Scored = 6 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS Six_Percentage
FROM Ball_by_Ball b
JOIN Matches m 
ON m.Match_Id = b.Match_Id
JOIN Player_Match pm
ON m.Match_Id = pm.Match_Id AND pm.Player_Id = b.Striker
JOIN Player p
ON pm.Player_Id = p.Player_Id
WHERE m.Season_Id IN (SELECT DISTINCT Season_Id FROM Matches WHERE Team_1 = 2 OR Team_2 = 2)
GROUP BY pm.Player_Id, p.Player_Name
ORDER BY Six_Percentage DESC, Four_Percentage DESC
LIMIT 15;

-- KPI #2 Bowling strike rate (Lower is better)
SELECT bb.Bowler, p.Player_Name,
       ROUND(COUNT(bb.Ball_Id) / COUNT(w.Player_Out),2) AS Strike_Rate
FROM ball_by_ball bb
LEFT JOIN wicket_taken w 
       ON bb.Match_Id = w.Match_Id 
       AND bb.Over_Id = w.Over_Id 
       AND bb.Ball_Id = w.Ball_Id
JOIN player p
ON p.Player_Id = bb.Bowler
WHERE bb.Team_Bowling = 2
GROUP BY bb.Bowler
HAVING Strike_Rate IS NOT NULL
ORDER BY Strike_Rate ASC
LIMIT 15;

-- Q13.	Using SQL, write a query to find out average wickets taken by each bowler in each venue. Also rank the gender according to the average value.
WITH player_wickets AS (
    SELECT v.Venue_Id, v.Venue_Name, 
           p.Player_Name, 
           COUNT(w.Player_Out) AS total_wickets, 
           COUNT(DISTINCT m.Match_Id) AS matches_played  -- Distinct matches where the player bowled
    FROM Wicket_Taken w
    JOIN Ball_by_Ball b 
        ON w.Match_Id = b.Match_Id 
       AND w.Over_Id = b.Over_Id 
       AND w.Ball_Id = b.Ball_Id
       AND w.Innings_No = b.Innings_No  -- Ensuring correct innings mapping
    JOIN Matches m 
        ON b.Match_Id = m.Match_Id
    JOIN Player_Match pm 
        ON pm.Match_Id = m.Match_Id 
       AND pm.Player_Id = b.Bowler  -- Ensuring only actual bowlers are counted
    JOIN Player p 
        ON p.Player_Id = pm.Player_Id
    JOIN Venue v 
        ON v.Venue_Id = m.Venue_Id
    GROUP BY v.Venue_Id, v.Venue_Name, p.Player_Name
),
unranked_table AS (
    SELECT Venue_Id, Venue_Name, Player_Name, 
           total_wickets, 
           matches_played,
           ROUND(total_wickets / matches_played, 2) AS avg_wickets
    FROM player_wickets
)
SELECT *, DENSE_RANK() OVER(ORDER BY avg_wickets DESC) AS Ranking
FROM unranked_table
WHERE matches_played > 10;

-- 14.Which of the given players have consistently performed well in past seasons? (will you use any visualization to solve the problem)
#Bowling performance
WITH Player_Season_Performance AS (
    SELECT 
        p.Player_Name, 
        s.Season_Year, 
        SUM(bbb.Runs_Scored) AS Total_Runs, 
        COUNT(wt.Player_Out) AS Total_Wickets,
        COUNT(DISTINCT m.Match_Id) AS Matches_Played
    FROM Player p
    INNER JOIN Ball_by_Ball bbb ON p.Player_Id = bbb.Striker
    LEFT JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
                              AND bbb.Over_Id = wt.Over_Id 
                              AND bbb.Ball_Id = wt.Ball_Id 
                              AND bbb.Innings_No = wt.Innings_No
    INNER JOIN Matches m ON bbb.Match_Id = m.Match_Id
    INNER JOIN Season s ON m.Season_Id = s.Season_Id
    WHERE p.Player_Id = bbb.Bowler OR p.Player_Id = bbb.Striker
    GROUP BY p.Player_Name, s.Season_Year
)
SELECT 
    Player_Name, 
    AVG(Total_Runs) AS Avg_Runs_Per_Season, 
    AVG(Total_Wickets) AS Avg_Wickets_Per_Season, 
    COUNT(Season_Year) AS Seasons_Played
FROM Player_Season_Performance
GROUP BY Player_Name
HAVING Seasons_Played > 3
ORDER BY Avg_Runs_Per_Season DESC, Avg_Wickets_Per_Season DESC
LIMIT 10;


-- 15.Are there players whose performance is more suited to specific venues or conditions?

-- BATSMAN VENUE-SPECIFIC PERFORMANCE
WITH Player_Venue_Batting AS (
    SELECT 
        p.Player_Id,
        p.Player_Name,
        v.Venue_Id,
        v.Venue_Name,
        c.City_Name,
        
        -- Venue-specific stats
        COUNT(DISTINCT b.Match_Id) AS Matches_At_Venue,
        COUNT(DISTINCT CONCAT(b.Match_Id, '-', b.Innings_No)) AS Innings_At_Venue,
        SUM(b.Runs_Scored) AS Total_Runs_At_Venue,
        COUNT(*) AS Balls_Faced_At_Venue,
        
        -- Performance metrics at venue
        ROUND(SUM(b.Runs_Scored) * 1.0 / 
              NULLIF(COUNT(DISTINCT CONCAT(b.Match_Id, '-', b.Innings_No)), 0), 2) AS Avg_At_Venue,
        ROUND((SUM(b.Runs_Scored) * 100.0) / NULLIF(COUNT(*), 0), 2) AS Strike_Rate_At_Venue,
        SUM(CASE WHEN b.Runs_Scored = 4 THEN 1 ELSE 0 END) AS Fours_At_Venue,
        SUM(CASE WHEN b.Runs_Scored = 6 THEN 1 ELSE 0 END) AS Sixes_At_Venue
        
    FROM Player p
    INNER JOIN Ball_by_Ball b ON p.Player_Id = b.Striker
    INNER JOIN Matches m ON b.Match_Id = m.Match_Id
    INNER JOIN Venue v ON m.Venue_Id = v.Venue_Id
    LEFT JOIN City c ON v.City_Id = c.City_Id
    GROUP BY p.Player_Id, p.Player_Name, v.Venue_Id, v.Venue_Name, c.City_Name
    HAVING COUNT(DISTINCT CONCAT(b.Match_Id, '-', b.Innings_No)) >= 5  -- Min 5 innings
),
Player_Overall_Batting AS (
    SELECT 
        p.Player_Id,
        ROUND(SUM(b.Runs_Scored) * 1.0 / 
              NULLIF(COUNT(DISTINCT CONCAT(b.Match_Id, '-', b.Innings_No)), 0), 2) AS Overall_Average,
        ROUND((SUM(b.Runs_Scored) * 100.0) / NULLIF(COUNT(*), 0), 2) AS Overall_Strike_Rate
    FROM Player p
    INNER JOIN Ball_by_Ball b ON p.Player_Id = b.Striker
    GROUP BY p.Player_Id
)
SELECT 
    pvb.Player_Name,
    pvb.Venue_Name,
    pvb.City_Name,
    pvb.Matches_At_Venue,
    pvb.Innings_At_Venue,
    pvb.Total_Runs_At_Venue,
    pvb.Avg_At_Venue AS Batting_Avg_At_Venue,
    pob.Overall_Average AS Overall_Batting_Avg,
    pvb.Strike_Rate_At_Venue,
    pob.Overall_Strike_Rate,
    
    -- Performance comparison
    ROUND(pvb.Avg_At_Venue - pob.Overall_Average, 2) AS Avg_Difference,
    ROUND(((pvb.Avg_At_Venue - pob.Overall_Average) * 100.0) / 
          NULLIF(pob.Overall_Average, 0), 2) AS Avg_Difference_Pct,
    
    -- Venue suitability classification
    CASE 
        WHEN pvb.Avg_At_Venue > pob.Overall_Average * 1.3 THEN 'Exceptional Venue (30%+ Better)'
        WHEN pvb.Avg_At_Venue > pob.Overall_Average * 1.2 THEN 'Excellent Venue (20%+ Better)'
        WHEN pvb.Avg_At_Venue > pob.Overall_Average * 1.1 THEN ' Good Venue (10%+ Better)'
        WHEN pvb.Avg_At_Venue < pob.Overall_Average * 0.7 THEN ' Difficult Venue (30%+ Worse)'
        WHEN pvb.Avg_At_Venue < pob.Overall_Average * 0.8 THEN ' Struggling Venue (20%+ Worse)'
        ELSE '➖ Average Performance'
    END AS Venue_Suitability,
    
    -- Power metrics
    pvb.Fours_At_Venue,
    pvb.Sixes_At_Venue,
    pvb.Fours_At_Venue + pvb.Sixes_At_Venue AS Total_Boundaries
    
FROM Player_Venue_Batting pvb
INNER JOIN Player_Overall_Batting pob ON pvb.Player_Id = pob.Player_Id
WHERE pob.Overall_Average >= 20  -- Only established batsmen
ORDER BY Avg_Difference_Pct DESC
LIMIT 20;
