-- 1. Insert permissions dynamically (omit id to let PostgreSQL handle auto-increment)
INSERT INTO webapi.sec_permission (value, description)
VALUES
    ('cohortdefinition:*:generate:OMRS:get', 'Generate Cohort on Source with SourceKey = OMRS'),
    ('cohortdefinition:*:report:OMRS:get', 'Get Inclusion Rule Report for Source with SourceKey = OMRS')
    ON CONFLICT (value) DO NOTHING;

-- 2. Insert roles dynamically
INSERT INTO webapi.sec_role (name)
VALUES
    ('Source user (OMRS)'),
    ('ohdsi')
    ON CONFLICT (name) DO NOTHING;

-- 3. Link permissions to 'Source user (OMRS)' role
INSERT INTO webapi.sec_role_permission (role_id, permission_id, status)
SELECT
    r.id,
    p.id,
    NULL
FROM webapi.sec_role r
         CROSS JOIN webapi.sec_permission p
WHERE r.name = 'Source user (OMRS)'
  AND p.value IN (
                  'cohortdefinition:*:generate:OMRS:get',
                  'cohortdefinition:*:report:OMRS:get'
    )
    ON CONFLICT DO NOTHING;

-- 4. Create users 'ohdsi' and 'admin'
INSERT INTO webapi.sec_user (login, name)
VALUES
    ('ohdsi', 'ohdsi'),
    ('admin', 'admin')
    ON CONFLICT (login) DO NOTHING;

-- 5. Dynamically assign roles by Role Name and User Login
INSERT INTO webapi.sec_user_role (user_id, role_id, status, origin)
SELECT
    u.id,
    r.id,
    NULL,
    'SYSTEM'
FROM webapi.sec_user u
         JOIN webapi.sec_role r ON r.name IN (
                                              'ohdsi',
                                              'public',
                                              'concept set creator',
                                              'cohort creator',
                                              'cohort reader',
                                              'Source user (OMRS)'
    )
WHERE u.login = 'ohdsi'

UNION ALL

SELECT
    u.id,
    r.id,
    NULL,
    'SYSTEM'
FROM webapi.sec_user u
         JOIN webapi.sec_role r ON r.name IN (
                                              'admin',
                                              'public'
    )
WHERE u.login = 'admin'
    ON CONFLICT DO NOTHING;