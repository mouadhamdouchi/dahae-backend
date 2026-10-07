-- 20260901115000_audit_actions_microphone.sql
--
-- Deux actions auditées de plus : couper et rendre le micro d'un élève.
--
-- Un fichier séparé, et pas trois lignes en tête de la migration suivante, pour une raison
-- mécanique : `alter type … add value` ne peut pas être utilisée dans la transaction qui
-- l'ajoute. Supabase applique un fichier par transaction, donc la valeur existe et est
-- utilisable au moment où la migration d'après s'exécute. Les mettre ensemble marcherait
-- aujourd'hui — le corps d'une fonction n'est que du texte à la création — et casserait le
-- jour où quelqu'un ajoute un `insert` de démonstration en bas du même fichier.
--
-- Pourquoi ces gestes sont audités alors que « lever la main » ne l'est pas : couper le micro
-- d'un élève est une décision d'un adulte sur un mineur pendant un cours, et c'est exactement
-- le genre de fait dont une famille peut demander compte (`context/security.md` §9). Lever la
-- main est un geste que l'élève fait sur lui-même.

alter type app.audit_action add value if not exists 'micMuted';
alter type app.audit_action add value if not exists 'micRestored';
