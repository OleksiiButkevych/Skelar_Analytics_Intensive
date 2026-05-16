-- =====================================================================
-- перевірка сирих даних
-- =====================================================================
SELECT * 
FROM public.marketing_ads_raw
LIMIT 100;





-- =====================================================================
-- перевірка дублікатів
-- =====================================================================
WITH check_deduplication AS (
    SELECT 
        ad_id,
        date,
        ROW_NUMBER() OVER (PARTITION BY ad_id, date ORDER BY timestamp DESC) as rn
    FROM public.marketing_ads_raw
)
SELECT 
    ad_id, 
    date, 
    COUNT(*) as records_count
FROM check_deduplication
WHERE rn = 1        -- дивимось тільки на відфільтровані дані
GROUP BY ad_id, date
HAVING COUNT(*) > 1; -- шукаємо, чи є десь більше ніж 1 рядок на дату





-- =====================================================================
-- перевірка загального spend (для можливості подальшої перевірки витрат по каналам. Ми знаємо орієнтири по каналам)
-- =====================================================================
WITH deduplicated_ads AS (
    SELECT 
        ad_id,
        date,
        (spend / 100.0) as spend,
        ROW_NUMBER() OVER (
            PARTITION BY ad_id, date 
            ORDER BY timestamp DESC
        ) as rn
    FROM public.marketing_ads_raw
)
SELECT 
    ROUND(SUM(spend)::numeric, 2) as total_spend_all_channels
FROM deduplicated_ads
WHERE rn = 1;






-- =====================================================================
-- фінальний запит
-- =====================================================================
WITH deduplicated_ads AS (
    -- Крок 1: Дедублікація
    SELECT 
        source,
        campaign_id,
        adset_id,
        ad_id,
        date,
        -- ДІЛИМО НА 100, бо дані в базі зберігаються в центах
        (spend / 100.0) as spend, 
        impressions,
        clicks,
        installs,
        registrations,
        ROW_NUMBER() OVER (
            PARTITION BY ad_id, date 
            ORDER BY timestamp DESC
        ) as rn
    FROM public.marketing_ads_raw
),

daily_channel_metrics AS (
    -- Крок 2: Денні метрики по каналах
    SELECT 
        source,
        date,
        SUM(spend) as daily_spend,
        SUM(impressions) as daily_impressions,
        SUM(clicks) as daily_clicks,
        SUM(installs) as daily_installs,
        SUM(registrations) as daily_registrations
    FROM deduplicated_ads
    WHERE rn = 1
    GROUP BY source, date
),

channel_totals AS (
    -- Крок 3: Агрегація за весь період + LTV
    SELECT 
        source,
        SUM(daily_spend) as total_spend,
        SUM(daily_impressions) as total_impressions,
        SUM(daily_clicks) as total_clicks,
        SUM(daily_installs) as total_installs,
        SUM(daily_registrations) as total_registrations,
        CASE 
            WHEN source = 'tiktok' THEN 8.50
            WHEN source = 'meta' THEN 6.20
            WHEN source = 'google' THEN 12.40
            ELSE 0 
        END as ltv
    FROM daily_channel_metrics
    GROUP BY source
)

-- Фінальний вивід
SELECT 
    source,
    ROUND(total_spend::numeric, 2) as total_spend,
    
    -- CPM = (Spend / Impressions) * 1000
    ROUND((total_spend / NULLIF(total_impressions, 0) * 1000)::numeric, 2) as cpm,
    
    -- CTR %
    ROUND((total_clicks::numeric / NULLIF(total_impressions, 0) * 100), 2) as ctr_pct,
    
    -- CR Click -> Install %
    ROUND((total_installs::numeric / NULLIF(total_clicks, 0) * 100), 2) as cr_click_install_pct,
    
    -- CR Install -> Reg %
    ROUND((total_registrations::numeric / NULLIF(total_installs, 0) * 100), 2) as cr_install_reg_pct,
    
    -- CAC = Spend / Registrations (тепер буде в доларах: наприклад, для Meta замість 3.10 стане 0.031 або відповідно до реєстрацій)
    ROUND((total_spend / NULLIF(total_registrations, 0))::numeric, 2) as cac,
    
    ROUND(ltv::numeric, 2) as ltv,
    
    -- LTV / CAC (коефіцієнт залишиться ТКИМ САМИМ, бо раніше ти порівнював центи з доларами, а тепер долари з доларами)
    ROUND((ltv / NULLIF((total_spend / NULLIF(total_registrations, 0)), 0))::numeric, 2) as "ltv/cac"
FROM channel_totals
ORDER BY "ltv/cac" DESC;




-- =====================================================================
-- Бонус: розбий CAC по місяцях
-- Дозволяє відстежити тренд вигорання креативів чи оптимізації кампаній
-- =====================================================================
WITH deduplicated_ads AS (
    SELECT 
        source,
        date,
        (spend / 100.0) as spend,
        registrations,
        ROW_NUMBER() OVER (
            PARTITION BY ad_id, date 
            ORDER BY timestamp DESC
        ) as rn
    FROM public.marketing_ads_raw
)
SELECT 
    source,
    TO_CHAR(date, 'YYYY-MM') as campaign_month,
    ROUND(SUM(spend)::numeric, 2) as monthly_spend,
    SUM(registrations) as monthly_registrations,
    ROUND((SUM(spend) / NULLIF(SUM(registrations), 0))::numeric, 2) as monthly_cac
FROM deduplicated_ads
WHERE rn = 1
GROUP BY source, TO_CHAR(date, 'YYYY-MM')
ORDER BY campaign_month ASC, source ASC;

