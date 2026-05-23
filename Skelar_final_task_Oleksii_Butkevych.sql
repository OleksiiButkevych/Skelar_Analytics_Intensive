WITH user_first_payment AS (
    -- 1. Знаходимо дату найпершого платежу для кожного користувача
    SELECT 
        id_user,
        MIN(date_created)::date AS first_pay_date
    FROM public.payments_encrypted
    GROUP BY id_user
),

cleaned_registrations AS (
    -- 2. Виконуємо умову: якщо дата першого платежу раніша за реєстрацію — 
    -- вважаємо її датою реєстрації. Якщо платежів не було — залишаємо як є.
    SELECT 
        r.id_user,
        LEAST(r.date_created::date, COALESCE(p.first_pay_date, r.date_created::date)) AS real_reg_date
    FROM public.registrations_encrypted r
    LEFT JOIN user_first_payment p ON r.id_user = p.id_user
),

weekly_revenue AS (
    -- 3. Рахуємо фактичну виручку за календарними тижнями успішних платежів
    SELECT 
        DATE_TRUNC('week', date_created)::date AS week_start,
        SUM(CASE WHEN status IN ('completed', 'success', 'approved', 'success_payment') THEN amount_original ELSE 0 END) AS actual_revenue
    FROM public.payments_encrypted
    WHERE date_created >= '2024-04-15' AND date_created <= '2024-06-02'
    GROUP BY 1
),

marketing_volume AS (
    -- 4. Рахуємо об'єм РЕАЛЬНОГО маркетингу (всі реєстрації, а не тільки успішні оплати)
    -- на основі вже скоригованих дат
    SELECT 
        DATE_TRUNC('week', real_reg_date)::date AS week_start,
        COUNT(id_user) AS total_regs
    FROM cleaned_registrations
    WHERE real_reg_date >= '2024-04-15' AND real_reg_date <= '2024-06-02'
    GROUP BY 1
),

marketing_drop_coef AS (
    -- 5. Розраховуємо чистий коефіцієнт падіння трафіку порівняно з піковим тижнем від 13.05
    SELECT 
        week_start,
        total_regs,
        1.0 - (total_regs::numeric / (SELECT total_regs FROM marketing_volume WHERE week_start = '2024-05-13')::numeric) AS market_drop_shf
    FROM marketing_volume
),

baseline_calcs AS (
    -- 6. Фіксуємо чистий Baseline виручки за 4 стабільні тижні до аварії
    SELECT 
        AVG(actual_revenue) AS baseline_revenue
    FROM weekly_revenue
    WHERE week_start IN ('2024-04-15', '2024-04-22', '2024-04-29', '2024-05-06')
)

-- 7. Фінальна візуалізація та математичний розподіл втрат
SELECT 
    r.week_start AS "Старт тижня",
    b.baseline_revenue::numeric(10,2) AS "Очікувана виручка (Baseline)",
    r.actual_revenue::numeric(10,2) AS "Фактична виручка",
    
    -- Загальний збиток (План мінус Факт) для періоду збою
    CASE 
        WHEN r.week_start >= '2024-05-13' AND (b.baseline_revenue - r.actual_revenue) > 0 
        THEN (b.baseline_revenue - r.actual_revenue)::numeric(10,2)
        ELSE 0 
    END AS "Загальний збиток тижня",
    
    -- Чистий технічний збиток
    CASE 
        -- Перші два тижні збою (13.05 та 20.05) — весь збиток списуємо на баг
        WHEN r.week_start IN ('2024-05-13', '2024-05-20') AND (b.baseline_revenue - r.actual_revenue) > 0 
        THEN (b.baseline_revenue - r.actual_revenue)::numeric(10,2)
        
        -- Третій тиждень (27.05) — віднімаємо від загального збитку ту частину, яку з'їв маркетинг
        WHEN r.week_start = '2024-05-27' 
        THEN (
            (b.baseline_revenue - r.actual_revenue) - 
            (b.baseline_revenue * GREATEST(0, m.market_drop_shf))
        )::numeric(10,2)
        ELSE 0 
    END AS "Збитки: Технічний збій",
    
    -- Втрати компанії через те, що маркетинг зменшив об'єми
    CASE 
        -- Проявляється лише на тижні від 27.05, коли навмисно прикрутили рекламу
        WHEN r.week_start = '2024-05-27' AND m.market_drop_shf > 0 
        THEN (b.baseline_revenue * m.market_drop_shf)::numeric(10,2)
        ELSE 0 
    END AS "Збитки: Зниження маркетингу"

FROM weekly_revenue r
CROSS JOIN baseline_calcs b
LEFT JOIN marketing_drop_coef m ON r.week_start = m.week_start
ORDER BY r.week_start ASC;




