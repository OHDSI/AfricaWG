set search_path = public;

CREATE INDEX IF NOT EXISTS idx_concept_name_lower
    ON public.concept (LOWER(concept_name))
    WHERE standard_concept = 'S' AND invalid_reason IS NULL;
CREATE INDEX IF NOT EXISTS idx_concept_name_lower_non_standard
    ON public.concept (LOWER(concept_name))
    WHERE standard_concept IS NULL AND invalid_reason IS NULL;