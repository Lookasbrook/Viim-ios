-- Trace, par alerte, que le conducteur a attesté le consentement de ses contacts d'urgence
-- (politique WhatsApp : chaque destinataire doit avoir accepté de recevoir ces messages).
-- Les contacts eux-mêmes ne sont pas persistés ; seule l'attestation l'est.
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS contacts_consent boolean;
