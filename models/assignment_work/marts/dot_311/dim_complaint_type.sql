-- Complaint type dimension for DOT 311 service requests.
-- Grain: one row per distinct (complaint_type, descriptor) combination.
WITH stg_311 AS (
    SELECT * FROM {{ ref('stg_nyc_311_dot') }}
),

distinct_complaint_types AS (
    SELECT DISTINCT
        complaint_type,
        descriptor
    FROM stg_311
    WHERE complaint_type IS NOT NULL
),

enriched AS (
    SELECT
        complaint_type,
        descriptor,
        -- Order matters. Match keywords without regard to case.
        CASE
            WHEN LOWER(descriptor) LIKE '%sidewalk%' THEN 'sidewalk'
            WHEN LOWER(descriptor) LIKE '%street%' THEN 'street'
            WHEN LOWER(descriptor) LIKE '%bike%' THEN 'bike'
            WHEN LOWER(descriptor) LIKE '%highway%' THEN 'highway'
            ELSE 'other'
        END AS complaint_category
    FROM distinct_complaint_types
),

dim_complaint_type AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'complaint_type', 'descriptor'
        ]) }} AS complaint_type_key,
        complaint_type,
        descriptor,
        complaint_category
    FROM enriched
)

SELECT * FROM dim_complaint_type
