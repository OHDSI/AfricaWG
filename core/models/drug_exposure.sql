MODEL(
        name omop_db.DRUG_EXPOSURE,
        kind FULL,
        columns(
                drug_exposure_id INT NOT NULL,
                person_id INT NOT NULL,
                drug_concept_id INT NOT NULL,
                drug_exposure_start_date DATE NOT NULL,
                drug_exposure_start_datetime TIMESTAMP,
                drug_exposure_end_date DATE NOT NULL,
                drug_exposure_end_datetime TIMESTAMP,
                verbatim_end_date DATE,
                drug_type_concept_id INT NOT NULL,
                stop_reason VARCHAR(20),
                refills INT,
                quantity NUMERIC,
                days_supply INT,
                sig TEXT,
                route_concept_id INT,
                lot_number VARCHAR(50),
                provider_id INT,
                visit_occurrence_id INT,
                visit_detail_id INT,
                drug_source_value VARCHAR(50),
                drug_source_concept_id INT,
                route_source_value VARCHAR(50),
                dose_unit_source_value VARCHAR(50)
        )
);

SELECT do.order_id                                                              AS drug_exposure_id,
       o.patient_id                                                             AS person_id,
       COALESCE(drug_cm.conceptId, 0)                                           AS drug_concept_id,
    DATE(o.date_activated)                                                   AS drug_exposure_start_date,
    o.date_activated                                                         AS drug_exposure_start_datetime,
    COALESCE(DATE(o.date_stopped), DATE(o.auto_expire_date), CURRENT_DATE)   AS drug_exposure_end_date,
    COALESCE(o.date_stopped, o.auto_expire_date, CURRENT_TIMESTAMP)          AS drug_exposure_end_datetime,
    DATE(COALESCE(o.date_stopped, o.auto_expire_date))                       AS verbatim_end_date,
    32838                                                                    AS drug_type_concept_id, -- EHR prescription
    LEFT(dc.order_reason_non_coded, 20)                                      AS stop_reason,
    do.num_refills                                                           AS refills,
    do.quantity                                                              AS quantity,
    NULL                                                                     AS days_supply,
    do.dosing_instructions                                                   AS sig,
    COALESCE(route_cm.conceptId, 0)                                          AS route_concept_id,
    NULL                                                                     AS lot_number,
    creator.user_id                                                          AS provider_id,
    e.visit_id                                                               AS visit_occurrence_id,
    NULL                                                                     AS visit_detail_id,
    LEFT(COALESCE(d.name, do.drug_non_coded, ''), 50)                        AS drug_source_value,
    COALESCE(drug_cm.conceptId, 0)                                           AS drug_source_concept_id,
       -- TODO: locale 'en' assumes an English OpenMRS installation; make configurable if needed
    LEFT(COALESCE(route_cn.name, ''), 50)                                    AS route_source_value,
    LEFT(COALESCE(dose_unit_cn.name, ''), 50)                                AS dose_unit_source_value
FROM openmrs.drug_order AS do
    INNER JOIN openmrs.orders AS o ON do.order_id = o.order_id
    LEFT JOIN openmrs.drug AS d ON do.drug_inventory_id = d.drug_id
    LEFT JOIN openmrs.encounter AS e ON o.encounter_id = e.encounter_id
    INNER JOIN openmrs.users AS creator ON o.creator = creator.user_id
    -- Filter domainId to prevent cross-domain concept bleed (mirrors observation.sql pattern)
    LEFT JOIN raw.CONCEPT_MAPPING drug_cm
    ON d.concept_id = drug_cm.sourceCode
    AND drug_cm.domainId = 'Drug'
    LEFT JOIN raw.CONCEPT_MAPPING route_cm
    ON do.route = route_cm.sourceCode
    -- Seed uses 'Meas Value' for route concepts (USAGI auto-generation artefact)
    AND route_cm.domainId IN ('Route', 'Meas Value')
    LEFT JOIN openmrs.concept_name route_cn
    ON do.route = route_cn.concept_id
    AND route_cn.locale = 'en'
    AND route_cn.concept_name_type = 'FULLY_SPECIFIED'
    LEFT JOIN openmrs.concept_name dose_unit_cn
    ON do.dose_units = dose_unit_cn.concept_id
    AND dose_unit_cn.locale = 'en'
    AND dose_unit_cn.concept_name_type = 'FULLY_SPECIFIED'
    -- Join to the corresponding DISCONTINUE order to retrieve the clinical stop reason
    LEFT JOIN openmrs.orders AS dc
    ON dc.previous_order_id = o.order_id
    AND dc.order_action = 'DISCONTINUE'
    AND dc.voided = 0
WHERE o.voided = 0
  AND o.date_activated IS NOT NULL
  AND (do.drug_inventory_id IS NOT NULL OR do.drug_non_coded IS NOT NULL);