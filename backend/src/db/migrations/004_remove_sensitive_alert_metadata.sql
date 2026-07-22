UPDATE alerts
SET metadata = metadata - 'medicalProfile',
    updated_at = now()
WHERE metadata ? 'medicalProfile';
