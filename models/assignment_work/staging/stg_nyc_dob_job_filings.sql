WITH source AS (
    SELECT * FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
),

cleaned AS (
    SELECT
        -- Keep other source columns for later dimension and fact models.
        * EXCEPT (
            job_filing_number,
            filing_status,
            job_type,
            filing_date,
            current_status_date,
            first_permit_date,
            approved_date,
            signoff_date,
            borough,
            council_district,
            postcode,
            zip,
            house_no,
            street_name,
            latitude,
            longitude,
            initial_cost,
            total_construction_floor_area,
            filing_representative_first_name,
            filing_representative_middle_initial,
            filing_representative_last_name,
            filing_representative_business_name,
            filing_representative_street_name,
            filing_representative_city,
            filing_representative_state,
            filing_representative_zip
        ),

        -- Identifiers and filing details. Keep suffixes such as -I1 and -S1.
        NULLIF(UPPER(TRIM(CAST(job_filing_number AS STRING))), '') AS job_filing_number,
        NULLIF(UPPER(TRIM(CAST(filing_status AS STRING))), '') AS filing_status,
        NULLIF(UPPER(TRIM(CAST(job_type AS STRING))), '') AS job_type,

        -- SAFE_CAST returns NULL for invalid values instead of failing the run.
        SAFE_CAST(filing_date AS TIMESTAMP) AS filing_date,
        SAFE_CAST(current_status_date AS TIMESTAMP) AS current_status_date,
        SAFE_CAST(first_permit_date AS TIMESTAMP) AS first_permit_date,
        SAFE_CAST(approved_date AS TIMESTAMP) AS approved_date,
        SAFE_CAST(signoff_date AS TIMESTAMP) AS signoff_date,

        -- Conformed location fields: same names and borough labels as 311.
        CASE
            WHEN NULLIF(TRIM(CAST(borough AS STRING)), '') IS NULL THEN NULL
            WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('MANHATTAN', 'NEW YORK COUNTY', '1') THEN 'Manhattan'
            WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('BRONX', 'THE BRONX', '2') THEN 'Bronx'
            WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('BROOKLYN', 'KINGS COUNTY', '3') THEN 'Brooklyn'
            WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY', '4') THEN 'Queens'
            WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('STATEN ISLAND', 'RICHMOND COUNTY', '5') THEN 'Staten Island'
            ELSE 'UNKNOWN or CITYWIDE'
        END AS borough,
        NULLIF(TRIM(CAST(council_district AS STRING)), '') AS council_district,

        CASE
            WHEN REGEXP_CONTAINS(TRIM(CAST(postcode AS STRING)), r'^\d{5}(-?\d{4})?$')
                THEN TRIM(CAST(postcode AS STRING))
            ELSE NULL
        END AS zip,
        NULLIF(TRIM(CAST(zip AS STRING)), '') AS applicant_zip,

        NULLIF(TRIM(CAST(house_no AS STRING)), '') AS house_no,
        NULLIF(TRIM(CAST(street_name AS STRING)), '') AS street_name,
        SAFE_CAST(latitude AS NUMERIC) AS latitude,
        SAFE_CAST(longitude AS NUMERIC) AS longitude,

        -- Numeric measures for analysis, rather than text values.
        SAFE_CAST(initial_cost AS NUMERIC) AS initial_cost,
        SAFE_CAST(total_construction_floor_area AS NUMERIC) AS total_construction_floor_area,

        -- Trim whitespace and turn blank strings into NULLs.
        NULLIF(TRIM(CAST(filing_representative_first_name AS STRING)), '')
            AS filing_representative_first_name,
        NULLIF(TRIM(CAST(filing_representative_middle_initial AS STRING)), '')
            AS filing_representative_middle_initial,
        NULLIF(TRIM(CAST(filing_representative_last_name AS STRING)), '')
            AS filing_representative_last_name,
        NULLIF(TRIM(CAST(filing_representative_business_name AS STRING)), '')
            AS filing_representative_business_name,
        NULLIF(TRIM(CAST(filing_representative_street_name AS STRING)), '')
            AS filing_representative_street_name,
        NULLIF(TRIM(CAST(filing_representative_city AS STRING)), '')
            AS filing_representative_city,
        NULLIF(UPPER(TRIM(CAST(filing_representative_state AS STRING))), '')
            AS filing_representative_state,
        CASE
            WHEN REGEXP_CONTAINS(
                TRIM(CAST(filing_representative_zip AS STRING)),
                r'^\d{5}(-?\d{4})?$'
            ) THEN TRIM(CAST(filing_representative_zip AS STRING))
            ELSE NULL
        END AS filing_representative_zip,

        CURRENT_TIMESTAMP() AS _stg_loaded_at

    FROM source
),

deduplicated AS (
    SELECT *
    FROM cleaned

    -- Only drop rows without a usable filing ID. Missing permit/signoff dates
    -- can be normal for unfinished filings, so do not filter those rows out.
    WHERE job_filing_number IS NOT NULL

    -- Choose the latest status for each filing, then the latest filing date.
    -- The final sort makes the choice stable when both dates tie; it does not
    -- imply that one tied row is more recent than another.
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY job_filing_number
        ORDER BY
            current_status_date DESC NULLS LAST,
            filing_date DESC NULLS LAST,
            TO_JSON_STRING(cleaned) DESC
    ) = 1
)

SELECT * FROM deduplicated
