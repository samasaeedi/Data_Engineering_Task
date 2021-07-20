/****** Object:  StoredProcedure [dbo].[sp_retailer_statistics]    Script Date: 7/9/2021 12:34:00 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- ======================================================================
-- Author:		Sama Saeedi
-- Create date: Friday, July 8,2021
-- Description:	Data Engineering task ## Extension
-- ======================================================================

CREATE OR ALTER   PROCEDURE [dbo].[sp_retailer_statistics] 

AS
BEGIN

/* CREATE RELATED TABLES FOR THE FIRST TIME */ 
DECLARE @create_table varchar(100)
	IF OBJECT_ID(N'[retailer_statistics]') IS NULL
	BEGIN
		CREATE TABLE [dbo].[retailer_statistics](
			[vendor] [varchar](255) ,
			[year_number] [int] ,
			[month_number] [int] ,
			[week_of_year] [int] ,
			[week_of_month] [int] ,
			[total_redemption] [int] ,
			[total_unique_users] [int] ,
			[best_selling_product] [varchar](255) ,
			[cumulative_redemption] [int] 
		)
	END;

DECLARE @p_max_year_retailers INT,
		@p_max_week_retailers INT,
		@p_max_year_vouchers INT,
		@p_max_month_vouchers INT,
		@p_max_week_vouchers INT,
		@p_firt_time INT,
		@p_table_has_data INT

/*  SET BEGIN_DATE FOR THE FIRST TIME */

select 
	@p_firt_time = count(*) 
from 
	(select top 1 * from retailer_statistics)  as rs

if @p_firt_time = 0  
	select 
		@p_max_year_retailers = datepart(YEAR,min(STIMULATED_DATE)) 
	from vouchers
else	
	select 
		@p_max_year_retailers = max(year_number)
	from retailer_statistics;

if @p_firt_time = 0  
	select 
		@p_max_week_retailers = datepart(WEEK,min(STIMULATED_DATE)) 
	from vouchers
	where 
		datepart(YEAR,STIMULATED_DATE) = @p_max_year_retailers
else		
	select 
		@p_max_week_retailers = max(week_of_year) 
	from retailer_statistics
	WHERE year_number= @p_max_year_retailers;

/* MAX DATE OF VOUCHERS TABLE */

select 
	@p_max_year_vouchers = datepart(YEAR,max(STIMULATED_DATE))
from vouchers

select 
	@p_max_week_vouchers = datepart(WEEK,max(STIMULATED_DATE))
from vouchers
WHERE
	DATEPART(YEAR,STIMULATED_DATE) =  @p_max_year_vouchers and
	DATEPART(WEEKDAY,STIMULATED_DATE) =7 

select 
	@p_max_month_vouchers = datepart(MONTH,max(STIMULATED_DATE))
from vouchers
WHERE
	DATEPART(YEAR,STIMULATED_DATE) =  @p_max_year_vouchers and
	DATEPART(WEEKDAY,STIMULATED_DATE) =7 


WHILE @p_max_week_retailers <= @p_max_week_vouchers
BEGIN

SELECT @p_table_has_data = count(*)  
FROM 
	retailer_statistics
WHERE 
	year_number= @p_max_year_retailers and
	week_of_year= @p_max_week_retailers

IF @p_table_has_data = 0
	BEGIN
		WITH
			voucher_detail as ( /* ADDING NEW DATE FIELDS TO VOUCHER TABLE */
							SELECT
								v.*,
								datepart(YEAR,STIMULATED_DATE) as year_number,
								datepart(MONTH,STIMULATED_DATE) as month_number,
								datepart(WEEK,STIMULATED_DATE) as week_of_year,
								(DATEPART(WEEK, STIMULATED_DATE) - DATEPART(WEEK, DATEADD(day, 1, EOMONTH(STIMULATED_DATE, -1)))) + 1 week_of_month		
							FROM 
								vouchers v
							  ),
			total_redeemed as ( /* CALCULATING "REDEEMED" STATUS GROUP BY EACH VENDOR AND WEEK */
							SELECT 
								vd_redeemed.vendor,
								vd_redeemed.week_of_month,
								count(*) as total_num_redeemed
							FROM 
								voucher_detail vd_redeemed
							WHERE vd_redeemed.status='redeemed'
							GROUP BY
								vd_redeemed.vendor,
								vd_redeemed.week_of_month
							   ),
			produc_selling as ( /* CALCULATING COUNT OF SELLING GROUP BY EACH VENDOR AND WEEK AND PRODUCT */
							SELECT 
								vendor,
								week_of_month,
								product,
								count(product)  as product_total_selling
							FROM 
								voucher_detail
							GROUP BY 
								vendor,
								week_of_month,
								product
							 ),
			product_selling_ranks as ( /* CALCULATING RANK OF PRODUCTS TO FIND THE BEST SELLING PRODUCT */
							SELECT 
								vendor,
								week_of_month,
								product_total_selling,
								product,
								row_number() over (partition by vendor,week_of_month order by product_total_selling desc) as product_rank
							FROM 
								produc_selling
							GROUP BY 
								vendor,
								week_of_month,
								product_total_selling,
								product
							)

		INSERT INTO 
			retailer_statistics 
			(
				vendor,
				year_number,
				month_number,
				week_of_year,
				week_of_month,
				total_redemption,
				total_unique_users,
				best_selling_product,
				cumulative_redemption
			)

			SELECT 
				vd_total.vendor,
				vd_total.year_number,
				vd_total.month_number,
				vd_total.week_of_year,
				vd_total.week_of_month,
				vd_redeemed.total_num_redeemed as total_redemption,
				count(distinct vd_total.user_id) as total_unique_users,
				psr.product as best_selling_product,
				sum(vd_redeemed.total_num_redeemed) over (partition by vd_total.vendor,vd_total.year_number order by vd_total.vendor,vd_total.week_of_year asc rows between unbounded preceding and current row) as cumulative_redemption
			FROM voucher_detail vd_total
			JOIN product_selling_ranks psr on vd_total.vendor=psr.vendor and vd_total.week_of_month=psr.week_of_month and psr.product_rank=1
			JOIN total_redeemed vd_redeemed on vd_total.vendor=vd_redeemed.VENDOR and vd_total.week_of_month=vd_redeemed.week_of_month
			GROUP BY
				vd_total.vendor,
				vd_total.year_number,
				vd_total.month_number,
				vd_total.week_of_year,
				vd_total.week_of_month,
				psr.product,
				vd_redeemed.total_num_redeemed ;
END;

SET @p_max_week_retailers = @p_max_week_retailers+1
END

END
GO
