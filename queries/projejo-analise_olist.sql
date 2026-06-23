--Duvida de negocio principal: quais clientes merecem campanha de retenção e quais não valem o esforço, 
--nesse periodo de vendas de 2016 ate 2018? E se a maioria dos clientes compram apenas uma unica vez, o que os diferencia dos que voltam à plataforma 
--para comprar novamente?


--Quantos clientes eu tenho na minha base?
SELECT 
	DISTINCT customer_unique_id 
FROM d_clientes

--Quantos clientes compraram apenas uma vez? --Quais clientes compraram mais de uma vez?


CREATE VIEW compra_unica as
SELECT 	
	t2.customer_unique_id,
	COUNT(*) as qtde_pedidos
FROM f_pedidos as t1
LEFT JOIN d_clientes as t2
	ON t1.customer_id = t2.customer_id
WHERE t1.order_status = 'delivered'
GROUP BY 1
HAVING COUNT(*) = 1


CREATE VIEW 
recompra as

SELECT 	
	t2.customer_unique_id,
	COUNT(*) as qtde_pedidos
FROM f_pedidos as t1
LEFT JOIN d_clientes as t2
	ON t1.customer_id = t2.customer_id
WHERE t1.order_status = 'delivered'
GROUP BY 1
HAVING COUNT(*) > 1
--A categoria dos pedidos tem influencia na diferenca de valor gasto medio geral entre quem compra apenas uma unica vez e quem recompra?
WITH cat_pedido_cliente as(
	SELECT 
		t4.customer_unique_id,
		t3.product_category_name,
		AVG(t2.price) as preco_medio
	FROM f_pedidos as t1
	LEFT JOIN f_itens as t2
		ON t1.order_id = t2.order_id
	LEFT JOIN d_produtos as t3
		ON t2.product_id = t3.product_id
	LEFT JOIN d_clientes as t4
		ON t1.customer_id = t4.customer_id
	WHERE order_status = 'delivered' 
	GROUP BY 1,2)
,preco_recompra as

	(SELECT 
		product_category_name,
		ROUND(AVG(preco_medio::numeric),2) as preco_medio_recompra
	FROM cat_pedido_cliente as t1
	INNER JOIN recompra as t2
		 ON t1.customer_unique_id = t2.customer_unique_id
	GROUP BY 1
	ORDER BY preco_medio_recompra DESC)
, preco_unica as
	

	(SELECT 
		product_category_name,
		ROUND(AVG(preco_medio::numeric),2) as preco_medio_unica
	FROM cat_pedido_cliente as t1
	INNER JOIN compra_unica as t2
		 ON t1.customer_unique_id = t2.customer_unique_id
	GROUP BY 1
	ORDER BY preco_medio_unica DESC)


SELECT 
	COALESCE(r.product_category_name, u.product_category_name) as categoria,
	r.preco_medio_recompra,
	u.preco_medio_unica,
	ROUND( u.preco_medio_unica - r.preco_medio_recompra, 2)  as diferenca
FROM preco_recompra as r
FULL OUTER JOIN preco_unica as u
	ON r.product_category_name = u.product_category_name
ORDER BY diferenca DESC;

--As avaliações tem relacao com a quantidade de clientes que recompraram?
WITH
review_por_cliente as(

	SELECT 
		customer_unique_id,
		ROUND(avg(review_score),1) as media_avaliacao
	
	FROM f_pedidos as t1
	LEFT JOIN f_reviews as t2
		ON t1.order_id=t2.order_id
	LEFT JOIN d_clientes as t3
		ON t1.customer_id = t3.customer_id
	WHERE order_status = 'delivered'
	GROUP BY 1
), resumo_avaliacao AS (
    SELECT 
		'Recompra' AS perfil, 
		ROUND(AVG(media_avaliacao),2) AS avaliacao 
	FROM review_por_cliente as t1 
	INNER JOIN recompra as t2 
		ON t1.customer_unique_id = t2.customer_unique_id
    UNION ALL
    SELECT 
		'Compra Única' AS perfil, 
		ROUND(AVG(media_avaliacao),2) AS avaliacao 
	FROM review_por_cliente as t1 
	INNER JOIN compra_unica as t2 
		ON t1.customer_unique_id = t2.customer_unique_id
)


--O preco dos produtos na primeira compra tem relacao com essa discrepancia?

,preco_medio as(

SELECT 
	t3.customer_unique_id,
	AVG(t2.price) as media_preco
FROM f_pedidos as t1
LEFT JOIN f_itens as t2
	ON t1.order_id = t2.order_id
LEFT JOIN d_clientes as t3
	ON t1.customer_id = t3.customer_id
WHERE order_status = 'delivered'
GROUP BY 1),
	
resumo_preco AS (
    SELECT 
		'Recompra' AS perfil, 
		ROUND(AVG(media_preco::numeric),2) as preco 
	FROM preco_medio as t1 
	INNER JOIN recompra as t2 
		ON t1.customer_unique_id = t2.customer_unique_id
    UNION ALL
    SELECT 'Compra Única' AS perfil, ROUND(AVG(media_preco::numeric),2) as preco 
	FROM preco_medio as t1 
	INNER JOIN compra_unica as t2 
		ON t1.customer_unique_id = t2.customer_unique_id
),


	
--O atraso na entrega dos pedidos pode influenciar a nao recompra?
atrasados as(

	SELECT 
		t1.customer_unique_id,
		order_delivered_customer_date::date as data_chegada,
		order_estimated_delivery_date::date as data_estimada,
		CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
		THEN 'Atrasado'
		ELSE 'No prazo'
		END AS status_pedido
		
	FROM d_clientes as t1
	LEFT JOIN f_pedidos as t2
		ON t1.customer_id = t2.customer_id
	WHERE order_status = 'delivered' and order_delivered_customer_date is not null

),
 dias_atraso as(

	SELECT 
		customer_unique_id,
		AVG(data_chegada::date - data_estimada::date) as media_atraso_dias
	FROM atrasados
	WHERE status_pedido = 'Atrasado'
	GROUP BY 1

 ), resumo_atraso AS (
    SELECT 
		'Recompra' AS perfil, 
		ROUND(AVG(media_atraso_dias),2) as atraso 
		FROM recompra as t1 
		INNER JOIN dias_atraso as t2 
			ON t1.customer_unique_id = t2.customer_unique_id
    UNION ALL 
    SELECT 
		'Compra Única' AS perfil, 
		ROUND(AVG(media_atraso_dias),2) as atraso 
		FROM compra_unica as t1 
		INNER JOIN dias_atraso as t2 
			ON t1.customer_unique_id = t2.customer_unique_id  
)


SELECT 
    a.perfil,
    a.avaliacao AS media_avaliacao,
    p.preco AS preco_medio_pedido,
    t.atraso AS media_dias_atraso
FROM resumo_avaliacao as a
JOIN resumo_preco as p ON a.perfil = p.perfil
JOIN resumo_atraso as t ON a.perfil = t.perfil;



















