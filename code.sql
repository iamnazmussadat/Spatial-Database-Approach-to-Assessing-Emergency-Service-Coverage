-- =================================================================
-- MASTER SQL SCRIPT: EMERGENCY SERVICE COVERAGE ANALYSIS (KARLSRUHE)
-- Goal: Identify road segments further than 1.5km from all services.
-- =================================================================

-- 1. DATA CLEANING & PREPARATION
-- -----------------------------------------------------------------
-- Recreating the combined point layer for all emergency facilities
CREATE TABLE emergency_facilities_karlsruhe AS
SELECT * 
FROM (
    SELECT * FROM fire_stations
    UNION ALL
    SELECT * FROM police_stations
    UNION ALL
    SELECT * FROM hospitals
) AS combined_facilities;

DROP TABLE IF EXISTS fire_stations, police_stations, hospitals CASCADE;

CREATE TABLE fire_stations AS 
SELECT * FROM emergency_facilities_karlsruhe WHERE amenity = 'fire_station';

CREATE TABLE police_stations AS 
SELECT * FROM emergency_facilities_karlsruhe WHERE amenity = 'police';

CREATE TABLE hospitals AS 
SELECT * FROM emergency_facilities_karlsruhe WHERE amenity = 'hospital';

-- Summary count for Methodology section
SELECT amenity, COUNT(*) as count 
FROM emergency_facilities_karlsruhe 
GROUP BY amenity ORDER BY amenity;


-- 2. CREATE SPATIAL COVERAGE LAYERS (For QGIS Visualization)
-- -----------------------------------------------------------------
DROP TABLE IF EXISTS fire_coverage_1_5km, police_coverage_1_5km, hospital_coverage_1_5km;

CREATE TABLE fire_coverage_1_5km AS
SELECT id, ST_Buffer(geom::geography, 1500)::geometry AS geom_zone FROM fire_stations;

CREATE TABLE police_coverage_1_5km AS
SELECT id, ST_Buffer(geom::geography, 1500)::geometry AS geom_zone FROM police_stations;

CREATE TABLE hospital_coverage_1_5km AS
SELECT id, ST_Buffer(geom::geography, 1500)::geometry AS geom_zone FROM hospitals;


-- 3. INDIVIDUAL SERVICE GAP ANALYSIS (1.5km Standard)
-- -----------------------------------------------------------------
DROP TABLE IF EXISTS road_gaps_fire, road_gaps_police, road_gaps_hospital, total_emergency_gaps;

-- Identify roads outside Fire service area
CREATE TABLE road_gaps_fire AS
SELECT r.id, r.geom FROM roads_karlsruhe r
WHERE NOT EXISTS (SELECT 1 FROM fire_stations f WHERE ST_DWithin(r.geom::geography, f.geom::geography, 1500));

-- Identify roads outside Police service area
CREATE TABLE road_gaps_police AS
SELECT r.id, r.geom FROM roads_karlsruhe r
WHERE NOT EXISTS (SELECT 1 FROM police_stations p WHERE ST_DWithin(r.geom::geography, p.geom::geography, 1500));

-- Identify roads outside Hospital service area
CREATE TABLE road_gaps_hospital AS
SELECT r.id, r.geom FROM roads_karlsruhe r
WHERE NOT EXISTS (SELECT 1 FROM hospitals h WHERE ST_DWithin(r.geom::geography, h.geom::geography, 1500));


-- 4. MULTI-CRITERIA VULNERABILITY ANALYSIS (The "Triple Gap")
-- -----------------------------------------------------------------
CREATE TABLE total_emergency_gaps AS
SELECT r.id, r.geom
FROM road_gaps_fire r
INNER JOIN road_gaps_police p ON r.id = p.id
INNER JOIN road_gaps_hospital h ON r.id = h.id;


-- 5. RESULTS & STATISTICS FOR REPORT
-- -----------------------------------------------------------------

-- Percentage results for all 3 services at 1.5km
SELECT 'Fire Stations (1.5km)' AS service, (SELECT COUNT(*) FROM road_gaps_fire)::float / COUNT(*)*100 AS pct_uncovered FROM roads_karlsruhe
UNION ALL
SELECT 'Police Stations (1.5km)', (SELECT COUNT(*) FROM road_gaps_police)::float / COUNT(*)*100 FROM roads_karlsruhe
UNION ALL
SELECT 'Hospitals (1.5km)', (SELECT COUNT(*) FROM road_gaps_hospital)::float / COUNT(*)*100 FROM roads_karlsruhe;


--Code for the Final Summary Table
SELECT 
    'Fire Gaps' AS analysis_layer, 
    '> 1500m from station' AS coverage_criteria,
    COUNT(*) AS count_of_gap_segments,
    (COUNT(*)::float / (SELECT COUNT(*) FROM roads_karlsruhe) * 100) AS percentage_of_network
FROM road_gaps_fire

UNION ALL

SELECT 
    'Police Gaps', 
    '> 1500m from station',
    COUNT(*),
    (COUNT(*)::float / (SELECT COUNT(*) FROM roads_karlsruhe) * 100)
FROM road_gaps_police

UNION ALL

SELECT 
    'Hospital Gaps', 
    '> 1500m from station',
    COUNT(*),
    (COUNT(*)::float / (SELECT COUNT(*) FROM roads_karlsruhe) * 100)
FROM road_gaps_hospital

UNION ALL

SELECT 
    'Total Vulnerability (Triple Gap)', 
    'Uncovered by ALL (1.5km)',
    COUNT(*),
    (COUNT(*)::float / (SELECT COUNT(*) FROM roads_karlsruhe) * 100)
FROM total_emergency_gaps;


-- FINAL HEADLINE RESULT: The 4.74% Triple Gap
SELECT 
    (SELECT COUNT(*) FROM total_emergency_gaps)::float / 
    (SELECT COUNT(*) FROM roads_karlsruhe)::float * 100 AS pct_final_standard_vulnerability;

-- DISTRICT ANALYSIS (Administrative Impact)
SELECT 
    b.name AS district_name, 
    COUNT(g.id) AS gap_count
FROM karlsruhe_city b 
JOIN total_emergency_gaps g ON ST_Intersects(b.geom, g.geom)
GROUP BY b.name
ORDER BY gap_count DESC;

