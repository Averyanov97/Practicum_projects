/* Анализ рынка недвижимости Санкт-Петербурга и Ленинградской области (ad hoc задачи)
 * Учебный проект программы «Аналитик данных» (Яндекс Практикум), выполнен самостоятельно.
 * СУБД: PostgreSQL, схема real_estate (учебная база Практикума, в репозиторий не входит).
 *
 * Автор: Аверьянов Игорь
 * Дата: 24.03.2026
 */


-- ============================================================
-- Запрос 1. Время активности объявлений по сегментам и регионам
-- ============================================================

-- Границы выбросов по 1-му и 99-му перцентилям
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area)     AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms)          AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony)        AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),

-- Объявления без выбросов (пропуски в признаках сохраняем)
filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
              AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
             OR ceiling_height IS NULL)
)

-- Сегменты по сроку экспозиции; объявления без days_exposition ещё не сняты с продажи
SELECT
    CASE
        WHEN a.days_exposition BETWEEN 1 AND 30   THEN '1-30 days'
        WHEN a.days_exposition BETWEEN 31 AND 90  THEN '31-90 days'
        WHEN a.days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
        WHEN a.days_exposition > 180              THEN '181+ days'
        ELSE 'active'
    END AS category,
    CASE
        WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
        ELSE 'ЛенОбл'
    END AS region,
    COUNT(a.id) AS total_ads,
    ROUND(COUNT(a.id) * 100.0 / SUM(COUNT(a.id)) OVER (
        PARTITION BY CASE WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург' ELSE 'ЛенОбл' END
    )) AS share_in_region,
    ROUND(AVG(a.last_price::numeric / f.total_area::numeric), 2) AS avg_price_per_sqm,
    ROUND(AVG(f.total_area::numeric), 2) AS avg_area,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.rooms)   AS median_rooms,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.balcony) AS median_balcony
FROM real_estate.advertisement AS a
JOIN real_estate.flats AS f   ON a.id = f.id
JOIN real_estate.city AS c    ON f.city_id = c.city_id
JOIN real_estate.type AS t    ON f.type_id = t.type_id
JOIN filtered_id AS fi        ON f.id = fi.id
WHERE a.first_day_exposition::date BETWEEN '2015-01-01' AND '2018-12-31'
  AND t.type = 'город'
GROUP BY category, region
ORDER BY total_ads DESC;


-- ============================================================
-- Запрос 2. Сезонность публикации и снятия объявлений
-- ============================================================

WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area)     AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms)          AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony)        AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),

filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
              AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
             OR ceiling_height IS NULL)
),

-- Месяц публикации и месяц снятия для объявлений 2015–2018 годов в городах.
-- Для активных объявлений (days_exposition IS NULL) месяц снятия не определён.
ads_month AS (
    SELECT
        a.id,
        EXTRACT(MONTH FROM a.first_day_exposition::timestamp) AS month_publication,
        EXTRACT(MONTH FROM a.first_day_exposition::timestamp
                           + a.days_exposition * INTERVAL '1 day') AS month_removal,
        a.last_price,
        f.total_area
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f   ON a.id = f.id
    JOIN real_estate.city AS c    ON f.city_id = c.city_id
    JOIN real_estate.type AS t    ON f.type_id = t.type_id
    JOIN filtered_id AS fi        ON f.id = fi.id
    WHERE a.first_day_exposition::date BETWEEN '2015-01-01' AND '2018-12-31'
      AND t.type = 'город'
),

-- Статистика по месяцу публикации
publication_stats AS (
    SELECT
        month_publication AS month,
        COUNT(*) AS ads_published,
        ROUND(AVG(last_price::numeric / total_area::numeric), 2) AS avg_price_per_sqm_published,
        ROUND(AVG(total_area::numeric), 2) AS avg_area_published
    FROM ads_month
    GROUP BY month_publication
),

-- Статистика по месяцу снятия (только снятые объявления)
removal_stats AS (
    SELECT
        month_removal AS month,
        COUNT(*) AS ads_removed,
        ROUND(AVG(last_price::numeric / total_area::numeric), 2) AS avg_price_per_sqm_removed,
        ROUND(AVG(total_area::numeric), 2) AS avg_area_removed
    FROM ads_month
    WHERE month_removal IS NOT NULL
    GROUP BY month_removal
)

SELECT
    p.month,
    p.ads_published,
    r.ads_removed,
    p.avg_price_per_sqm_published,
    r.avg_price_per_sqm_removed,
    p.avg_area_published,
    r.avg_area_removed
FROM publication_stats AS p
LEFT JOIN removal_stats AS r ON p.month = r.month
ORDER BY p.month;
