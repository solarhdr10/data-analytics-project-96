WITH buffer AS (
    SELECT
        s.visitor_id,
        s.visit_date,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        l.lead_id,
        l.created_at,
      l.amount,
      l.closing_reason,
      l.status_id,
      ROW_NUMBER() OVER (PARTITION BY s.visitor_id ORDER BY s.visit_date DESC) AS rn
    FROM sessions AS s
    LEFT JOIN leads AS l
      ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
    WHERE
      s.medium <> 'organic'
  )
  SELECT
    utm_source,
    COUNT(DISTINCT visitor_id) AS visitors_count,
    COUNT(DISTINCT CASE WHEN NOT lead_id IS NULL THEN visitor_id END) AS leads_count,
    COUNT(DISTINCT CASE WHEN status_id = 142 THEN visitor_id END) AS purchases_count,
    SUM(CASE WHEN NOT lead_id IS NULL THEN amount ELSE 0 END) AS revenue
  FROM buffer
  WHERE
    rn = 1
  GROUP BY
    utm_source
  ORDER BY
    visitors_count DESC


SELECT
    ROUND(CAST(COUNT(DISTINCT b.lead_id) * 1.0 / COUNT(DISTINCT b.visitor_id) AS DECIMAL), 4) * 100 AS lead_conversion_rate,
    ROUND(
      CAST(COUNT(CASE WHEN b.status_id = 142 THEN 1 END) * 1.0 / COUNT(DISTINCT b.lead_id) AS DECIMAL),
      4
    ) * 100 AS lead_to_purchase_conversion_rate,
    ROUND(
      CAST(COUNT(CASE WHEN b.status_id = 142 THEN 1 END) * 1.0 / COUNT(DISTINCT b.visitor_id) AS DECIMAL),
      4
    ) * 100 AS purchase_conversion_rate
  FROM buffer AS b
  WHERE
    b.rn = 1


aggr_last AS (
    SELECT
      b.utm_source,
      b.utm_medium,
      b.utm_campaign,
      CAST(b.visit_date AS DATE) AS visit_date,
      COUNT(b.visitor_id) AS visitors_count,
      COUNT(b.lead_id) AS leads_count,
      COUNT(CASE WHEN b.status_id = 142 THEN b.visitor_id END) AS purchases_count,
      SUM(CASE WHEN b.status_id = 142 THEN b.amount END) AS revenue
    FROM buffer AS b
    WHERE
      b.rn = 1
    GROUP BY
      b.utm_source,
      b.utm_medium,
      b.utm_campaign,
      CAST(b.visit_date AS DATE)
  ), ads_costs AS (
    SELECT
      CAST(va.campaign_date AS DATE) AS campaign_date,
      va.utm_source,
      va.utm_medium,
      va.utm_campaign,
      SUM(va.daily_spent) AS total_cost
    FROM vk_ads AS va
    GROUP BY
      CAST(va.campaign_date AS DATE),
      va.utm_source,
      va.utm_medium,
      va.utm_campaign
    UNION
    SELECT
      CAST(ya.campaign_date AS DATE) AS campaign_date,
      ya.utm_source,
      ya.utm_medium,
      ya.utm_campaign,
      SUM(ya.daily_spent) AS total_cost
    FROM ya_ads AS ya
    GROUP BY
      CAST(ya.campaign_date AS DATE),
      ya.utm_source,
      ya.utm_medium,
      ya.utm_campaign
  ), final AS (
    SELECT
      al.visit_date,
      al.visitors_count,
      al.utm_source,
      al.utm_medium,
      al.utm_campaign,
      ac.total_cost,
      al.leads_count,
      al.purchases_count,
      al.revenue
    FROM aggr_last AS al

    LEFT JOIN ads_costs AS ac
      ON al.visit_date = ac.campaign_date
      AND al.utm_medium = ac.utm_medium
      AND al.utm_campaign = ac.utm_campaign
      AND al.utm_source = ac.utm_source
    ORDER BY
      al.revenue DESC NULLS LAST,
      al.visit_date ASC,
      al.visitors_count DESC,
      al.utm_source ASC,
      al.utm_medium ASC
  )
  SELECT
    utm_source AS Источник,
    SUM(total_cost) AS Затраты,
    SUM(revenue) AS Прибыль
  FROM final
  WHERE
    utm_source = 'vk' OR utm_source = 'yandex'
  GROUP BY
    utm_source



    SELECT
    EXTRACT(DAY FROM visit_date) AS date,
    COUNT(DISTINCT visitor_id) AS visitors_count,
    COUNT(DISTINCT CASE WHEN NOT lead_id IS NULL THEN visitor_id END) AS leads_count,
    COUNT(DISTINCT CASE WHEN status_id = 142 THEN visitor_id END) AS purchases_count
  FROM buffer
  WHERE
    rn = 1
  GROUP BY
    date
  ORDER BY
    date ASC



    SELECT
  DATE_TRUNC('DAY', campaign_date) AS campaign_date,
  utm_source AS utm_source,
  MAX(total_cost) AS "MAX(total_cost)"
FROM (
  SELECT
    CAST(campaign_date AS DATE) AS campaign_date,
    utm_source,
    SUM(daily_spent) AS total_cost
  FROM (
    SELECT
      campaign_date,
      utm_source,
      utm_medium,
      utm_campaign,
      daily_spent
    FROM vk_ads
    UNION ALL
    SELECT
      campaign_date,
      utm_source,
      utm_medium,
      utm_campaign,
      daily_spent
    FROM ya_ads
  ) AS combined_ads
  GROUP BY
    campaign_date,
    utm_source
  ORDER BY
    campaign_date
) AS virtual_table
WHERE
  TRUE
GROUP BY
  DATE_TRUNC('DAY', campaign_date),
  utm_source
ORDER BY
  "MAX(total_cost)" DESC




  final AS (
    SELECT
      al.visit_date,
      al.visitors_count,
      al.utm_source,
      al.utm_medium,
      al.utm_campaign,
      ac.total_cost,
      al.leads_count,
      al.purchases_count,
      al.revenue
    FROM aggr_last AS al
    LEFT JOIN ads_costs AS ac
      ON al.visit_date = ac.campaign_date
      AND al.utm_medium = ac.utm_medium
      AND al.utm_campaign = ac.utm_campaign
      AND al.utm_source = ac.utm_source
    ORDER BY
      al.revenue DESC NULLS LAST,
      al.visit_date ASC,
      al.visitors_count DESC,
      al.utm_source ASC,
      al.utm_medium ASC
  )
  SELECT
    ROUND(SUM(total_cost) / SUM(visitors_count), 2) AS "Стоимость за клик",
    ROUND(SUM(total_cost) / SUM(leads_count), 2) AS "Стоимость лида",
    ROUND(SUM(total_cost) / SUM(purchases_count), 2) AS "Стоимость покупателя",
    ROUND((
      SUM(revenue) - SUM(total_cost)
    ) / SUM(total_cost) * 100, 2) AS ROI
  FROM final
  HAVING
    NOT ROUND(SUM(total_cost) / SUM(visitors_count), 2) IS NULL
