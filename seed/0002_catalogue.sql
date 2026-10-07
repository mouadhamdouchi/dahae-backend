-- 0002_catalogue.sql — GENERATED, do not edit by hand.
--
-- Written by backend/seed/generate-catalogue.mjs from
-- frontend/lib/demo-data/catalogue.ts, which reads the real syllabus in
-- programme.ts (DEC-051). Correct a chapter there and run the generator again.
--
-- Idempotent: every statement is an upsert on a natural key. Run it after
-- 0001_reference.sql.
--
-- Order matters in one place. A subject cannot be published without a free first
-- chapter (DEC-034) and the database refuses it, so the nine subjects go in
-- unpublished, the chapters follow, and the last statement publishes them.

-- Streams. Names live in the three message catalogues, keyed by slug: there are three
-- of them, they are a closed set for the MVP, and one copy is enough.
insert into public.tracks (slug, level, filiere, position, published) values
  ('1bac', '1bac'::app.level, null, 1, true),
  ('2bac-sciences-economiques', '2bac'::app.level, 'sciences-economiques'::app.filiere, 2, true),
  ('2bac-sgc', '2bac'::app.level, 'sgc'::app.filiere, 3, true)
on conflict (slug) do update
  set level = excluded.level,
      filiere = excluded.filiere,
      position = excluded.position,
      published = excluded.published;

-- The same three subjects run in every stream (DEC-030).
insert into public.subjects (slug, position) values
  ('comptabilite-maths-financieres', 1),
  ('economie-generale-statistiques', 2),
  ('eoae', 3)
on conflict (slug) do update set position = excluded.position;

-- Nine teaching units. Left unpublished here on purpose; the last statement of this
-- file publishes them, once their chapters exist.
insert into public.track_subjects (track_id, subject_id, modality, published)
select t.id, s.id, 'hybrid'::app.modality, false
from public.tracks t cross join public.subjects s
on conflict (track_id, subject_id) do nothing;

-- The offer (DEC-030, DEC-036, DEC-049). Amounts are placeholders and every screen that
-- shows one carries the demonstration warning until the real prices arrive (F5) —
-- `is_demo_price` is what makes that warning truthful rather than decorative.
insert into public.packs (slug, subject_count, price_minor, currency, billing, is_demo_price, published, position) values
  ('pack-1', 1, 120000, 'MAD', 'per_semester', true, true, 1),
  ('pack-2', 2, 200000, 'MAD', 'per_semester', true, true, 2),
  ('pack-3', 3, 270000, 'MAD', 'per_semester', true, true, 3)
on conflict (slug) do update
  set subject_count = excluded.subject_count,
      price_minor = excluded.price_minor,
      currency = excluded.currency,
      is_demo_price = excluded.is_demo_price,
      published = excluded.published,
      position = excluded.position;

-- 79 chapters of the official syllabus: 42 in the first semester,
-- 37 in the second, 9 free first chapters — one per subject, which is
-- the promise the catalogue makes on every card (DEC-034).
insert into public.lessons (
  track_subject_id, position, slug,
  title_fr, title_ar, title_en,
  summary_fr, summary_ar, summary_en,
  semester, is_free_preview, published
)
select
  ts.id, v.ordinal_position, v.slug,
  v.title_fr, v.title_ar, v.title_en,
  v.summary_fr, v.summary_ar, v.summary_en,
  v.semester::app.semester, v.is_free_preview, true
from (values
  ('1bac', 'comptabilite-maths-financieres', 1, 'le-bilan', 'Le bilan', 'الميزانية', 'The balance sheet', 'Emplois et ressources, actif et passif, et la lecture d’un premier bilan.', 'الاستخدامات والموارد، الأصول والخصوم، وقراءة أول ميزانية.', 'Uses and resources, assets and liabilities, and reading a first balance sheet.', 's1', true),
  ('1bac', 'comptabilite-maths-financieres', 2, 'compte-journal', 'Le compte et le journal comptable', 'الحساب واليومية المحاسبية', 'The account and the journal', 'Débit et crédit, fonctionnement des comptes et passage au journal.', 'المدين والدائن، اشتغال الحسابات والانتقال إلى اليومية.', 'Debit and credit, how accounts work, and posting to the journal.', 's1', false),
  ('1bac', 'comptabilite-maths-financieres', 3, 'cpc', 'Le compte de produits et charges', 'حساب العائدات والتكاليف', 'The income statement', 'Charges, produits et formation du résultat sur un exercice.', 'التكاليف والعائدات وتكوين النتيجة خلال السنة المحاسبية.', 'Expenses, income and how the result is formed over a period.', 's1', false),
  ('1bac', 'comptabilite-maths-financieres', 4, 'facturation', 'La facturation', 'الفوترة', 'Invoicing', 'Facture doit et facture avoir, réductions commerciales et financières.', 'فاتورة الدين وفاتورة الأصل، التخفيضات التجارية والمالية.', 'Invoices and credit notes, trade and cash discounts.', 's1', false),
  ('1bac', 'comptabilite-maths-financieres', 5, 'reglements-effets', 'Les règlements et les effets de commerce', 'التسويات والأوراق التجارية', 'Settlements and bills of exchange', 'Règlements au comptant, création et circulation des effets.', 'الأداء نقدا، إنشاء الأوراق التجارية وتداولها.', 'Cash settlements, and creating and circulating bills.', 's1', false),
  ('1bac', 'comptabilite-maths-financieres', 6, 'immobilisations', 'Les acquisitions d’immobilisations', 'اقتناء الأصول الثابتة', 'Acquiring fixed assets', 'Achat et production d’immobilisations, et les titres de placement.', 'شراء وإنتاج الأصول الثابتة، وسندات التوظيف.', 'Buying and producing fixed assets, and marketable securities.', 's2', false),
  ('1bac', 'comptabilite-maths-financieres', 7, 'travaux-paie', 'Les travaux de paie', 'أشغال الأجور', 'Payroll operations', 'Du salaire brut au net, cotisations et charges patronales.', 'من الأجر الخام إلى الصافي، الاشتراكات وتحملات المشغل.', 'From gross to net pay, contributions and employer charges.', 's2', false),
  ('1bac', 'comptabilite-maths-financieres', 8, 'interets-simples', 'Les intérêts simples et l’escompte commercial', 'الفوائد البسيطة والخصم التجاري', 'Simple interest and commercial discount', 'Calcul des intérêts, escompte et équivalence des effets.', 'حساب الفوائد، الخصم وتكافؤ الأوراق التجارية.', 'Interest calculation, discounting and equivalence of bills.', 's2', false),
  ('1bac', 'comptabilite-maths-financieres', 9, 'interets-composes', 'Les intérêts composés et l’équivalence des capitaux', 'الفوائد المركبة وتكافؤ الرساميل', 'Compound interest and equivalence of capital', 'Capitalisation, actualisation et comparaison de deux capitaux.', 'الرسملة، التحيين ومقارنة رأسمالين.', 'Capitalisation, discounting and comparing two capital sums.', 's2', false),
  ('1bac', 'economie-generale-statistiques', 1, 'fondements', 'Les fondements de la science économique', 'أسس علم الاقتصاد', 'The foundations of economics', 'Besoins, biens, rareté et les grandes questions de l’économie.', 'الحاجيات، الخيرات، الندرة والأسئلة الكبرى للاقتصاد.', 'Needs, goods, scarcity and the central questions of economics.', 's1', true),
  ('1bac', 'economie-generale-statistiques', 2, 'activite-economique', 'L’activité économique', 'النشاط الاقتصادي', 'Economic activity', 'Agents économiques, opérations et secteurs institutionnels.', 'الأعوان الاقتصاديون، العمليات والقطاعات المؤسساتية.', 'Economic agents, operations and institutional sectors.', 's1', false),
  ('1bac', 'economie-generale-statistiques', 3, 'circuit-simplifie', 'Le circuit économique simplifié', 'الدورة الاقتصادية المبسطة', 'The simplified economic circuit', 'Flux réels et flux monétaires entre les agents.', 'التدفقات الحقيقية والنقدية بين الأعوان.', 'Real and monetary flows between agents.', 's1', false),
  ('1bac', 'economie-generale-statistiques', 4, 'production', 'La production', 'الإنتاج', 'Production', 'Facteurs de production, combinaison productive et productivité.', 'عوامل الإنتاج، التوليفة الإنتاجية والإنتاجية.', 'Factors of production, the production mix and productivity.', 's1', false),
  ('1bac', 'economie-generale-statistiques', 5, 'repartition-revenus', 'La répartition et la redistribution des revenus', 'توزيع وإعادة توزيع الدخل', 'Distribution and redistribution of income', 'Revenus primaires, prélèvements, transferts et revenu disponible.', 'الدخول الأولية، الاقتطاعات، التحويلات والدخل المتاح.', 'Primary income, levies, transfers and disposable income.', 's2', false),
  ('1bac', 'economie-generale-statistiques', 6, 'consommation-epargne', 'La consommation et l’épargne', 'الاستهلاك والادخار', 'Consumption and saving', 'Propension à consommer, structure de la consommation et épargne.', 'الميل للاستهلاك، بنية الاستهلاك والادخار.', 'Propensity to consume, the structure of consumption, and saving.', 's2', false),
  ('1bac', 'economie-generale-statistiques', 7, 'investissement', 'L’investissement', 'الاستثمار', 'Investment', 'Nature, déterminants et effets de l’investissement.', 'طبيعة الاستثمار، محدداته وآثاره.', 'The nature, drivers and effects of investment.', 's2', false),
  ('1bac', 'economie-generale-statistiques', 8, 'statistique-descriptive', 'Les outils de la statistique descriptive', 'أدوات الإحصاء الوصفي', 'Tools of descriptive statistics', 'Séries à une variable, position et dispersion.', 'السلاسل ذات متغير واحد، مؤشرات الموقع والتشتت.', 'Single-variable series, measures of position and dispersion.', 's2', false),
  ('1bac', 'eoae', 1, 'approche-classique', 'L’approche classique de l’entreprise', 'المقاربة الكلاسيكية للمقاولة', 'The classical view of the firm', 'Définitions, classifications et finalités de l’entreprise.', 'تعاريف المقاولة، تصنيفاتها وغاياتها.', 'Definitions, classifications and purposes of the firm.', 's1', true),
  ('1bac', 'eoae', 2, 'approche-systemique', 'L’approche systémique de l’entreprise', 'المقاربة النسقية للمقاولة', 'The systemic view of the firm', 'L’entreprise comme système ouvert sur son environnement.', 'المقاولة كنسق منفتح على محيطه.', 'The firm as a system open to its environment.', 's1', false),
  ('1bac', 'eoae', 3, 'entreprise-cellule-humaine', 'L’entreprise, cellule humaine', 'المقاولة كخلية بشرية', 'The firm as a human cell', 'Groupes, pouvoir et relations entre les acteurs internes.', 'الجماعات، السلطة والعلاقات بين الفاعلين الداخليين.', 'Groups, power and relations between internal actors.', 's1', false),
  ('1bac', 'eoae', 4, 'organisation-travail', 'L’organisation du travail', 'تنظيم العمل', 'Work organisation', 'Conceptions classiques et modernes de l’organisation du travail.', 'التصورات الكلاسيكية والحديثة لتنظيم العمل.', 'Classical and modern approaches to organising work.', 's1', false),
  ('1bac', 'eoae', 5, 'gestion-temps', 'La gestion du temps', 'تدبير الوقت', 'Time management', 'Planification, priorités et outils de gestion du temps.', 'التخطيط، الأولويات وأدوات تدبير الوقت.', 'Planning, priorities and time-management tools.', 's2', false),
  ('1bac', 'eoae', 6, 'information-entreprise', 'L’information dans l’entreprise', 'المعلومة داخل المقاولة', 'Information inside the firm', 'Recherche, codification, collecte et diffusion de l’information.', 'البحث عن المعلومة، ترميزها، جمعها ونشرها.', 'Finding, coding, collecting and circulating information.', 's2', false),
  ('1bac', 'eoae', 7, 'qualite-totale', 'La qualité totale', 'الجودة الشاملة', 'Total quality', 'Conception de la qualité, démarche qualité et cercles de qualité.', 'مفهوم الجودة، مسار الجودة وحلقات الجودة.', 'The idea of quality, quality processes and quality circles.', 's2', false),
  ('1bac', 'eoae', 8, 'certification', 'La certification', 'الإشهاد', 'Certification', 'La certification comme argument commercial et engagement.', 'الإشهاد كحجة تجارية والتزام.', 'Certification as a commercial argument and a commitment.', 's2', false),
  ('2bac-sciences-economiques', 'comptabilite-maths-financieres', 1, 'regularisation-stocks', 'La régularisation des stocks', 'تسوية المخزونات', 'Adjusting inventory', 'Variation de stock et écritures de fin d’exercice.', 'تغير المخزون وتسجيلات نهاية السنة.', 'Stock movement and year-end entries.', 's1', true),
  ('2bac-sciences-economiques', 'comptabilite-maths-financieres', 2, 'amortissements', 'Les amortissements', 'الاهتلاكات', 'Depreciation', 'Taux, annuités, plans et tableaux d’amortissement.', 'النسب، الأقساط، مخططات وجداول الاهتلاك.', 'Rates, annual charges, schedules and depreciation tables.', 's1', false),
  ('2bac-sciences-economiques', 'comptabilite-maths-financieres', 3, 'provisions-creances', 'Les provisions sur créances clients', 'مؤونات ديون الزبناء', 'Provisions on trade receivables', 'Clients douteux, dotation et reprise de provision.', 'الزبناء المشكوك فيهم، تكوين المؤونة واستردادها.', 'Doubtful customers, charging and releasing provisions.', 's1', false),
  ('2bac-sciences-economiques', 'comptabilite-maths-financieres', 4, 'provisions-titres', 'Les provisions sur titres', 'مؤونات السندات', 'Provisions on securities', 'Titres de participation et titres et valeurs de placement.', 'سندات المساهمة وسندات وقيم التوظيف.', 'Equity holdings and marketable securities.', 's1', false),
  ('2bac-sciences-economiques', 'comptabilite-maths-financieres', 5, 'provisions-risques', 'Les provisions pour risques et charges', 'مؤونات المخاطر والتكاليف', 'Provisions for risks and charges', 'Risques identifiés, stocks, terrains et fonds commercial.', 'المخاطر المحددة، المخزونات، الأراضي والأصل التجاري.', 'Identified risks, inventory, land and goodwill.', 's1', false),
  ('2bac-sciences-economiques', 'comptabilite-maths-financieres', 6, 'regularisation-charges-produits', 'La régularisation des charges et des produits', 'تسوية التكاليف والعائدات', 'Adjusting expenses and income', 'Charges à payer, produits à recevoir et comptes de régularisation.', 'التكاليف المستحقة، العائدات المنتظرة وحسابات التسوية.', 'Accrued expenses, income receivable and accrual accounts.', 's2', false),
  ('2bac-sciences-economiques', 'comptabilite-maths-financieres', 7, 'analyse-bilan', 'L’analyse du bilan', 'دراسة الميزانية', 'Balance-sheet analysis', 'Bilan financier, fonds de roulement, trésorerie et ratios.', 'الميزانية المالية، رأس المال العامل، الخزينة والنسب.', 'Financial balance sheet, working capital, cash and ratios.', 's2', false),
  ('2bac-sciences-economiques', 'comptabilite-maths-financieres', 8, 'esg', 'L’analyse d’exploitation : l’ESG', 'تحليل الاستغلال: جدول أرصدة التدبير', 'Operating analysis: management balances', 'Marge, valeur ajoutée, EBE et capacité d’autofinancement.', 'الهامش، القيمة المضافة، الفائض الخام للاستغلال والقدرة على التمويل الذاتي.', 'Margin, value added, gross operating surplus and self-financing.', 's2', false),
  ('2bac-sciences-economiques', 'comptabilite-maths-financieres', 9, 'ted', 'L’analyse d’exploitation : le TED', 'تحليل الاستغلال: جدول الاستغلال التفاضلي', 'Operating analysis: the differential table', 'Charges variables et fixes, seuil de rentabilité et levier.', 'التكاليف المتغيرة والثابتة، عتبة المردودية والرافعة.', 'Variable and fixed costs, break-even point and leverage.', 's2', false),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 1, 'marche', 'Le marché', 'السوق', 'The market', 'Offre, demande, formation des prix et structures de marché.', 'العرض، الطلب، تكوين الأثمان وبنيات السوق.', 'Supply, demand, price formation and market structures.', 's1', true),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 2, 'circuit-economique', 'Le circuit économique', 'الدورة الاقتصادية', 'The economic circuit', 'Relations entre agents et équilibre emplois-ressources.', 'العلاقات بين الأعوان وتوازن الاستخدامات والموارد.', 'Relations between agents and the uses-resources balance.', 's1', false),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 3, 'agregats', 'Les agrégats de la comptabilité nationale', 'المجاميع الاقتصادية للمحاسبة الوطنية', 'National accounting aggregates', 'PIB, RNBD, consommation finale et calcul des agrégats.', 'الناتج الداخلي الخام، الدخل الوطني، الاستهلاك النهائي وحساب المجاميع.', 'GDP, national income, final consumption and how aggregates are computed.', 's1', false),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 4, 'inflation', 'L’inflation', 'التضخم', 'Inflation', 'Mesure, causes, effets et politiques de lutte contre l’inflation.', 'قياس التضخم، أسبابه، آثاره وسياسات مواجهته.', 'Measurement, causes, effects and anti-inflation policy.', 's1', false),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 5, 'chomage', 'Le chômage', 'البطالة', 'Unemployment', 'Formes, mesure, causes et politiques de l’emploi.', 'أشكال البطالة، قياسها، أسبابها وسياسات التشغيل.', 'Types, measurement, causes and employment policy.', 's1', false),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 6, 'politique-monetaire', 'La politique monétaire', 'السياسة النقدية', 'Monetary policy', 'Objectifs, instruments et action de Bank Al-Maghrib.', 'الأهداف، الأدوات وتدخل بنك المغرب.', 'Objectives, instruments and the action of Bank Al-Maghrib.', 's2', false),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 7, 'politique-budgetaire', 'La politique budgétaire', 'السياسة الميزانياتية', 'Fiscal policy', 'Loi de finances, dépenses, recettes et solde budgétaire.', 'قانون المالية، النفقات، المداخيل ورصيد الميزانية.', 'The finance act, spending, revenue and the budget balance.', 's2', false),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 8, 'echanges-exterieurs', 'Les échanges extérieurs', 'المبادلات الخارجية', 'External trade', 'Balance commerciale, balance des paiements et taux de change.', 'الميزان التجاري، ميزان الأداءات وسعر الصرف.', 'Trade balance, balance of payments and exchange rates.', 's2', false),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 9, 'developpement', 'Le développement', 'التنمية', 'Development', 'Croissance et développement, indicateurs et stratégies.', 'النمو والتنمية، المؤشرات والاستراتيجيات.', 'Growth versus development, indicators and strategies.', 's2', false),
  ('2bac-sciences-economiques', 'economie-generale-statistiques', 10, 'mondialisation', 'La mondialisation et l’ouverture de l’économie', 'العولمة وانفتاح الاقتصاد', 'Globalisation and economic openness', 'Manifestations, acteurs, effets et place du Maroc.', 'مظاهر العولمة، فاعلوها، آثارها وموقع المغرب.', 'How it shows, its actors, its effects and Morocco’s position.', 's2', false),
  ('2bac-sciences-economiques', 'eoae', 1, 'notion-strategie', 'La notion de stratégie', 'مفهوم الاستراتيجية', 'The idea of strategy', 'Métier, mission, finalités et objectifs de l’entreprise.', 'المهنة، الرسالة، الغايات وأهداف المقاولة.', 'The firm’s business, mission, purposes and objectives.', 's1', true),
  ('2bac-sciences-economiques', 'eoae', 2, 'planification-strategique', 'La planification stratégique', 'التخطيط الاستراتيجي', 'Strategic planning', 'Diagnostic interne et externe, et démarche de planification.', 'التشخيص الداخلي والخارجي ومسار التخطيط.', 'Internal and external diagnosis, and the planning process.', 's1', false),
  ('2bac-sciences-economiques', 'eoae', 3, 'options-strategiques', 'Les options stratégiques', 'الخيارات الاستراتيجية', 'Strategic options', 'Spécialisation, diversification, intégration et externalisation.', 'التخصص، التنويع، الاندماج والاستعانة بالخارج.', 'Specialisation, diversification, integration and outsourcing.', 's1', false),
  ('2bac-sciences-economiques', 'eoae', 4, 'croissance', 'La croissance de l’entreprise', 'نمو المقاولة', 'Company growth', 'Croissance interne et externe, et modalités de financement.', 'النمو الداخلي والخارجي وطرق التمويل.', 'Internal and external growth, and how it is financed.', 's1', false),
  ('2bac-sciences-economiques', 'eoae', 5, 'concentration', 'La concentration des entreprises', 'تركز المقاولات', 'Business concentration', 'Formes de concentration et effets sur le marché.', 'أشكال التركز وآثاره على السوق.', 'Forms of concentration and their effect on the market.', 's1', false),
  ('2bac-sciences-economiques', 'eoae', 6, 'enjeux-grh', 'Les enjeux et les domaines de la GRH', 'رهانات ومجالات تدبير الموارد البشرية', 'The stakes and scope of HR management', 'Rôle de la GRH et relations humaines dans l’entreprise.', 'دور تدبير الموارد البشرية والعلاقات الإنسانية داخل المقاولة.', 'What HR management is for, and human relations at work.', 's2', false),
  ('2bac-sciences-economiques', 'eoae', 7, 'recrutement', 'Le recrutement', 'التوظيف', 'Recruitment', 'Besoin, sources, sélection et intégration du candidat.', 'الحاجة، المصادر، الانتقاء وإدماج المترشح.', 'The need, sources, selection and onboarding.', 's2', false),
  ('2bac-sciences-economiques', 'eoae', 8, 'formation-carrieres', 'La formation et la gestion des carrières', 'التكوين وتدبير المسار المهني', 'Training and career management', 'Plan de formation, promotion, mobilité et plan social.', 'مخطط التكوين، الترقية، الحركية والمخطط الاجتماعي.', 'Training plans, promotion, mobility and redundancy plans.', 's2', false),
  ('2bac-sciences-economiques', 'eoae', 9, 'remuneration', 'La rémunération', 'الأجور', 'Pay', 'Politique salariale, formes de rémunération et motivation.', 'السياسة الأجرية، أشكال الأجر والتحفيز.', 'Pay policy, forms of remuneration and motivation.', 's2', false),
  ('2bac-sgc', 'comptabilite-maths-financieres', 1, 'travaux-fin-exercice', 'Les travaux de fin d’exercice', 'أشغال نهاية السنة المحاسبية', 'Year-end procedures', 'Pourquoi et comment on arrête les comptes d’un exercice.', 'لماذا وكيف تُقفل حسابات السنة المحاسبية.', 'Why and how the accounts of a period are closed.', 's1', true),
  ('2bac-sgc', 'comptabilite-maths-financieres', 2, 'regularisation-stocks', 'La régularisation des stocks', 'تسوية المخزونات', 'Adjusting inventory', 'Inventaire, variation de stock et écritures correspondantes.', 'الجرد، تغير المخزون والتسجيلات المقابلة.', 'Stocktaking, stock movement and the matching entries.', 's1', false),
  ('2bac-sgc', 'comptabilite-maths-financieres', 3, 'amortissements', 'Les amortissements', 'الاهتلاكات', 'Depreciation', 'Modes d’amortissement, plans et cession d’immobilisation.', 'أنماط الاهتلاك، المخططات والتفويت في الأصول.', 'Depreciation methods, schedules and asset disposal.', 's1', false),
  ('2bac-sgc', 'comptabilite-maths-financieres', 4, 'provisions', 'Les provisions', 'المؤونات', 'Provisions', 'Provisions sur créances, titres, stocks, risques et charges.', 'مؤونات الديون، السندات، المخزونات، المخاطر والتكاليف.', 'Provisions on receivables, securities, stock, risks and charges.', 's1', false),
  ('2bac-sgc', 'comptabilite-maths-financieres', 5, 'etats-synthese', 'Les états de synthèse', 'القوائم التركيبية', 'Financial statements', 'Bilan, CPC et documents de synthèse normalisés.', 'الميزانية، حساب العائدات والتكاليف والقوائم المعيارية.', 'Balance sheet, income statement and the standard statements.', 's1', false),
  ('2bac-sgc', 'comptabilite-maths-financieres', 6, 'esg-sgc', 'L’état des soldes de gestion', 'جدول أرصدة التدبير', 'The management balances statement', 'Marge, valeur ajoutée, EBE et capacité d’autofinancement.', 'الهامش، القيمة المضافة، الفائض الخام للاستغلال والقدرة على التمويل الذاتي.', 'Margin, value added, gross operating surplus and self-financing.', 's2', false),
  ('2bac-sgc', 'comptabilite-maths-financieres', 7, 'investissement-financement', 'Les choix d’investissement et de financement', 'اختيارات الاستثمار والتمويل', 'Investment and financing choices', 'Rentabilité d’un projet et comparaison des sources de financement.', 'مردودية المشروع ومقارنة مصادر التمويل.', 'Project profitability and comparing sources of finance.', 's2', false),
  ('2bac-sgc', 'comptabilite-maths-financieres', 8, 'annuites-emprunts', 'Les annuités et l’emprunt indivis', 'الدفعات والقرض غير المجزأ', 'Annuities and the indivisible loan', 'Annuités constantes, tableaux d’amortissement d’un emprunt.', 'الدفعات الثابتة وجداول اهتلاك القرض.', 'Constant annuities and loan amortisation tables.', 's2', false),
  ('2bac-sgc', 'comptabilite-maths-financieres', 9, 'comptabilite-analytique', 'La comptabilité analytique d’exploitation', 'المحاسبة التحليلية للاستغلال', 'Cost accounting', 'Charges directes et indirectes, coûts, stocks et résultats analytiques.', 'التكاليف المباشرة وغير المباشرة، الكلف، المخزونات والنتائج التحليلية.', 'Direct and indirect costs, cost build-up, stock and analytical results.', 's2', false),
  ('2bac-sgc', 'economie-generale-statistiques', 1, 'marche', 'Le marché', 'السوق', 'The market', 'Offre, demande, prix et structures de marché.', 'العرض، الطلب، الثمن وبنيات السوق.', 'Supply, demand, price and market structures.', 's1', true),
  ('2bac-sgc', 'economie-generale-statistiques', 2, 'circuit-elargi', 'Le circuit économique élargi', 'الدورة الاقتصادية الموسعة', 'The extended economic circuit', 'Agents, extérieur et institutions financières dans le circuit.', 'الأعوان، الخارج والمؤسسات المالية داخل الدورة.', 'Agents, the rest of the world and financial institutions.', 's1', false),
  ('2bac-sgc', 'economie-generale-statistiques', 3, 'agregats', 'Les agrégats de la comptabilité nationale', 'المجاميع الاقتصادية للمحاسبة الوطنية', 'National accounting aggregates', 'PIB, revenu national et équilibre emplois-ressources.', 'الناتج الداخلي الخام، الدخل الوطني وتوازن الاستخدامات والموارد.', 'GDP, national income and the uses-resources balance.', 's1', false),
  ('2bac-sgc', 'economie-generale-statistiques', 4, 'limites-comptabilite-nationale', 'Les limites de la comptabilité nationale', 'حدود المحاسبة الوطنية', 'The limits of national accounting', 'Ce que les agrégats ne mesurent pas, et les indicateurs alternatifs.', 'ما لا تقيسه المجاميع، والمؤشرات البديلة.', 'What the aggregates miss, and the alternative indicators.', 's1', false),
  ('2bac-sgc', 'economie-generale-statistiques', 5, 'regulation-marche', 'L’insuffisance de la régulation par le marché', 'قصور التنظيم عبر السوق', 'Where the market falls short', 'Défaillances du marché et justification de l’intervention publique.', 'إخفاقات السوق ومبررات التدخل العمومي.', 'Market failures and the case for public intervention.', 's2', false),
  ('2bac-sgc', 'economie-generale-statistiques', 6, 'politique-economique', 'La politique économique', 'السياسة الاقتصادية', 'Economic policy', 'Objectifs, carré magique et instruments de l’État.', 'الأهداف، المربع السحري وأدوات الدولة.', 'Objectives, the magic square and the state’s instruments.', 's2', false),
  ('2bac-sgc', 'economie-generale-statistiques', 7, 'politique-monetaire-budgetaire', 'La politique monétaire et la politique budgétaire', 'السياسة النقدية والسياسة الميزانياتية', 'Monetary and fiscal policy', 'Instruments, effets attendus et limites de chaque politique.', 'الأدوات، الآثار المنتظرة وحدود كل سياسة.', 'Instruments, intended effects and the limits of each.', 's2', false),
  ('2bac-sgc', 'economie-generale-statistiques', 8, 'echanges-ouverture', 'Les échanges extérieurs et l’ouverture de l’économie', 'المبادلات الخارجية وانفتاح الاقتصاد', 'External trade and economic openness', 'Mesure des échanges, balance des paiements et ouverture du Maroc.', 'قياس المبادلات، ميزان الأداءات وانفتاح المغرب.', 'Measuring trade, the balance of payments and Morocco’s openness.', 's2', false),
  ('2bac-sgc', 'eoae', 1, 'approvisionnement-achat', 'L’approvisionnement et l’achat', 'التموين والشراء', 'Sourcing and purchasing', 'Besoin, choix du fournisseur et processus d’achat.', 'الحاجة، اختيار المورد ومسار الشراء.', 'The need, choosing a supplier and the purchasing process.', 's1', true),
  ('2bac-sgc', 'eoae', 2, 'gestion-stocks', 'La gestion des stocks', 'تدبير المخزونات', 'Inventory management', 'Niveaux de stock, cadence d’approvisionnement et coûts.', 'مستويات المخزون، وتيرة التموين والتكاليف.', 'Stock levels, reorder rhythm and costs.', 's1', false),
  ('2bac-sgc', 'eoae', 3, 'organisation-production', 'L’organisation de la production', 'تنظيم الإنتاج', 'Organising production', 'Étapes préparatoires et contraintes de l’atelier.', 'المراحل التحضيرية وإكراهات الورشة.', 'Preparation stages and workshop constraints.', 's1', false),
  ('2bac-sgc', 'eoae', 4, 'fonction-financiere', 'La fonction financière', 'الوظيفة المالية', 'The finance function', 'Place et rôles de la fonction financière dans l’entreprise.', 'مكانة وأدوار الوظيفة المالية داخل المقاولة.', 'Where finance sits in the firm and what it does.', 's1', false),
  ('2bac-sgc', 'eoae', 5, 'solvabilite-rentabilite', 'La solvabilité et la rentabilité', 'الملاءة والمردودية', 'Solvency and profitability', 'Lecture financière de l’entreprise et principaux ratios.', 'القراءة المالية للمقاولة وأهم النسب.', 'Reading the firm financially, and the main ratios.', 's1', false),
  ('2bac-sgc', 'eoae', 6, 'financement', 'Le financement de l’exploitation et de l’investissement', 'تمويل الاستغلال والاستثمار', 'Financing operations and investment', 'Besoins de financement à court et à long terme.', 'حاجيات التمويل على المدى القصير والبعيد.', 'Short-term and long-term financing needs.', 's2', false),
  ('2bac-sgc', 'eoae', 7, 'mercatique', 'Le marché et la mercatique', 'السوق والتسويق', 'The market and marketing', 'Étude de marché, segmentation et démarche mercatique.', 'دراسة السوق، التقطيع والمسار التسويقي.', 'Market research, segmentation and the marketing approach.', 's2', false),
  ('2bac-sgc', 'eoae', 8, 'politique-produit-prix', 'La politique de produit et de prix', 'سياسة المنتوج والثمن', 'Product and pricing policy', 'Gamme, cycle de vie du produit et fixation du prix.', 'التشكيلة، دورة حياة المنتوج وتحديد الثمن.', 'Product range, life cycle and price setting.', 's2', false),
  ('2bac-sgc', 'eoae', 9, 'communication-distribution', 'La politique de communication et de distribution', 'سياسة التواصل والتوزيع', 'Communication and distribution policy', 'Moyens de communication et choix des canaux de distribution.', 'وسائل التواصل واختيار قنوات التوزيع.', 'Communication channels and choosing distribution channels.', 's2', false)
) as v (
  track_slug, subject_slug, ordinal_position, slug,
  title_fr, title_ar, title_en,
  summary_fr, summary_ar, summary_en,
  semester, is_free_preview
)
join public.tracks t on t.slug = v.track_slug
join public.subjects s on s.slug = v.subject_slug
join public.track_subjects ts on ts.track_id = t.id and ts.subject_id = s.id
on conflict (track_subject_id, slug) do update
  set position = excluded.position,
      title_fr = excluded.title_fr,
      title_ar = excluded.title_ar,
      title_en = excluded.title_en,
      summary_fr = excluded.summary_fr,
      summary_ar = excluded.summary_ar,
      summary_en = excluded.summary_en,
      semester = excluded.semester,
      is_free_preview = excluded.is_free_preview,
      published = excluded.published;

-- Now that every subject has its free first chapter, the trigger will let them through.
update public.track_subjects set published = true where not published;
