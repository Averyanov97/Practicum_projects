/* «Секреты Тёмнолесья»: анализ внутриигровых покупок
 * Учебный проект программы «Аналитик данных» (Яндекс Практикум), выполнен самостоятельно.
 * СУБД: PostgreSQL, схема fantasy (учебная база Практикума, в репозиторий не входит).
 *
 * Цель: изучить, как характеристики игроков и их персонажей связаны с покупкой
 * внутриигровой валюты «райские лепестки», и оценить активность игроков в покупках.
 *
 * Автор: Аверьянов Игорь
 * Дата: 15.01.2026
 */


-- ============================================================
-- 1. Исследовательский анализ
-- ============================================================

-- 1.1. Доля платящих игроков по всей игре
WITH share_paying AS (
    SELECT
        COUNT(id) AS total_users,                                   -- всего зарегистрированных игроков
        SUM(CASE WHEN payer = 1 THEN 1 ELSE 0 END) AS payer_users,  -- платящие игроки
        ROUND(SUM(CASE WHEN payer = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(id), 4) AS share_payer_users  -- доля платящих
    FROM fantasy.users
)
SELECT *
FROM share_paying;


-- 1.2. Доля платящих игроков по расе персонажа
WITH share_race_users AS (
    SELECT
        u.race_id,
        r.race,
        SUM(CASE WHEN u.payer = 1 THEN 1 ELSE 0 END) AS paying_users,  -- платящие игроки расы
        COUNT(u.id) AS total_users,                                    -- все игроки расы
        ROUND(SUM(CASE WHEN u.payer = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(u.id), 4) AS share_paying_users  -- доля платящих внутри расы
    FROM fantasy.users AS u
    LEFT JOIN fantasy.race AS r USING (race_id)
    GROUP BY u.race_id, r.race
)
SELECT *
FROM share_race_users
ORDER BY share_paying_users DESC;


-- 1.3. Статистика стоимости покупок (без покупок с нулевой стоимостью)
WITH stat_amount AS (
    SELECT
        COUNT(*) AS total_events,                                   -- число покупок
        SUM(amount) AS sum_amount,                                  -- суммарная стоимость
        ROUND(MIN(amount)::numeric, 2) AS min_amount,
        ROUND(MAX(amount)::numeric, 2) AS max_amount,
        ROUND(AVG(amount)::numeric, 2) AS avg_amount,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount,
        ROUND(STDDEV(amount::numeric), 2) AS std_amount
    FROM fantasy.events
    WHERE amount > 0
)
SELECT *
FROM stat_amount;


-- 1.4. Покупки с нулевой стоимостью: число и доля от всех покупок
WITH zero_events AS (
    SELECT
        COUNT(*) AS total_zero_events,
        ROUND(COUNT(*)::numeric / (SELECT COUNT(*) FROM fantasy.events), 4) AS share_zero_events
    FROM fantasy.events
    WHERE amount = 0
)
SELECT *
FROM zero_events;


-- 1.5. Популярность эпических предметов
WITH epic_items AS (                -- покупки эпических предметов с ненулевой стоимостью
    SELECT
        e.id AS user_id,
        i.game_items
    FROM fantasy.events AS e
    LEFT JOIN fantasy.items AS i ON e.item_code = i.item_code
    WHERE e.amount > 0
),
totals AS (
    SELECT
        COUNT(*) AS total_events,               -- всего покупок
        COUNT(DISTINCT user_id) AS total_users  -- всего покупателей
    FROM epic_items
)
SELECT
    ei.game_items,
    COUNT(*) AS total_sales,                                                    -- продажи предмета
    ROUND(COUNT(*)::numeric / t.total_events, 4) AS share_sales,                -- доля в продажах
    COUNT(DISTINCT ei.user_id) AS total_buyers,                                 -- покупатели предмета
    ROUND(COUNT(DISTINCT ei.user_id)::numeric / t.total_users, 4) AS share_buyers  -- доля покупателей предмета среди всех покупателей
FROM epic_items AS ei
CROSS JOIN totals AS t
GROUP BY ei.game_items, t.total_events, t.total_users
ORDER BY share_buyers DESC;


-- ============================================================
-- 2. Ad hoc: зависимость активности покупателей от расы персонажа
-- ============================================================

-- Все игроки по расам
WITH all_users AS (
    SELECT
        race_id,
        COUNT(id) AS all_users
    FROM fantasy.users
    GROUP BY race_id
),
-- Игроки с хотя бы одной покупкой ненулевой стоимости
buyers AS (
    SELECT DISTINCT
        u.id,
        u.race_id
    FROM fantasy.users AS u
    JOIN fantasy.events AS e USING (id)
    WHERE e.amount > 0
),
buyers_by_race AS (
    SELECT
        race_id,
        COUNT(DISTINCT id) AS total_buyers
    FROM buyers
    GROUP BY race_id
),
-- Доля платящих среди покупателей
share_payer AS (
    SELECT
        u.race_id,
        ROUND(COUNT(DISTINCT CASE WHEN u.payer = 1 THEN e.id END)::numeric / COUNT(DISTINCT e.id), 4) AS share_payers_among_buyers
    FROM fantasy.users AS u
    JOIN fantasy.events AS e USING (id)
    WHERE e.amount > 0
    GROUP BY u.race_id
),
-- Активность каждого покупателя
buyer_activity AS (
    SELECT
        u.id,
        u.race_id,
        COUNT(e.transaction_id) AS total_events,
        AVG(e.amount) AS avg_amount,
        SUM(e.amount) AS sum_amount
    FROM fantasy.users AS u
    JOIN fantasy.events AS e USING (id)
    WHERE e.amount > 0
    GROUP BY u.id, u.race_id
),
-- Средние показатели активности покупателей по расам
race_activity AS (
    SELECT
        race_id,
        AVG(total_events) AS avg_events_per_buyer,
        AVG(avg_amount) AS avg_amount_per_buyer,
        AVG(sum_amount) AS avg_sum_per_buyer
    FROM buyer_activity
    GROUP BY race_id
)
SELECT
    au.race_id,
    r.race,
    au.all_users,                                                          -- все игроки
    b.total_buyers,                                                        -- игроки с покупками
    ROUND(b.total_buyers::numeric / au.all_users, 4) AS share_buyers,      -- доля игроков с покупками
    sp.share_payers_among_buyers,                                          -- доля платящих среди покупателей
    ROUND(ra.avg_events_per_buyer::numeric, 4) AS avg_events_per_buyer,    -- среднее число покупок на покупателя
    ROUND(ra.avg_amount_per_buyer::numeric, 4) AS avg_amount_per_buyer,    -- средняя стоимость покупки на покупателя
    ROUND(ra.avg_sum_per_buyer::numeric, 4) AS avg_sum_per_buyer           -- средняя суммарная стоимость покупок на покупателя
FROM all_users AS au
LEFT JOIN buyers_by_race AS b   USING (race_id)
LEFT JOIN share_payer AS sp     USING (race_id)
LEFT JOIN race_activity AS ra   USING (race_id)
LEFT JOIN fantasy.race AS r     USING (race_id)
ORDER BY au.all_users DESC;
