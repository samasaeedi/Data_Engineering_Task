/****** Object:  StoredProcedure [dbo].[sp_import_json_files]    Script Date: 7/9/2021 12:34:12 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- ======================================================================
-- Author:		Sama Saeedi
-- Create date: Friday, July 8,2021
-- Description:	Data Engineering task ## Initial task
-- NOTE : ************ Please set JSON file path on line 72 ************ 
-- ======================================================================

CREATE OR ALTER     PROCEDURE [dbo].[sp_import_json_files]

AS
BEGIN

/* CREATE RELATED TABLES FOR THE FIRST TIME */ 
DECLARE @create_table varchar(100)
	IF OBJECT_ID(N'[VOUCHERS]') IS NULL
	BEGIN
		CREATE TABLE [VOUCHERS](
			[STIMULATED_DATE] [date] NULL,
			[USER_ID] [int] NULL,
			[VOUCHER_CODE] [varchar](100) NULL,
			[PRODUCT] [varchar](100) NULL,
			[VENDOR_CATEGORY] [varchar](100) NULL,
			[VENDOR] [varchar](100) NULL,
			[STATUS] [varchar](100) NULL
	)
	END;

	IF OBJECT_ID(N'[VOUCHERS_JSON_FILE]') IS NULL
	BEGIN
		CREATE TABLE [dbo].[VOUCHERS_JSON_FILE](
			[jsonfile_key] [date] NULL,
			[jsonfile_value] [varchar](max) NULL,
			[jsonfile_type] [int] NULL,
			[creation_date] [datetime] NULL
	)
	END;

------------------------------------------------------------------------------------------------------------
Declare 
		@p_jsonfile_path varchar(100)   ,
		@p_jsonfile_name varchar(10)	,
		@sqlquery varchar(max)			,
		@begin_date date				,
		@end_date date					,
		@firt_time int					
		

/*  SET BEGIN_DATE */
select 
	@firt_time = count(*)
from 
	(select top 1 * from vouchers_json_file)  as jf

if @firt_time = 0 
	set @begin_date = '2019-11-01'	
else
	select 
		@begin_date = dateadd(dd,1,max(jsonfile_key)) 
	from vouchers_json_file;

/*  HARD CODE PARAMETERS */
set @end_date = '2019-12-01';
set @p_jsonfile_path = 'D:\Wefarm\Data';

/*  LOOP FOR IMPORT JSON FILES */
WHILE @begin_date < @end_date
	BEGIN
		SET @p_jsonfile_name = @begin_date

		SET @sqlquery= '
		Declare @JSON varchar(max),
				@p_jsonfile_key varchar(10),
				@p_table_has_data int

		SELECT @JSON=BulkColumn
		FROM OPENROWSET (BULK ''' + @p_jsonfile_path+'\vouchers-'+@p_jsonfile_name+'.json'+ ''' , SINGLE_CLOB) import
		INSERT INTO vouchers_json_file 
									(
									JSONFILE_KEY,
									JSONFILE_VALUE,
									JSONFILE_TYPE,
									creation_DATE
									)
		SELECT 
			jsonfile.[key] as jsonfile_key,
			jsonfile.[value] as jsonfile_value,
			jsonfile.[type] as jsonfile_type,
			getdate() as creation_date
		FROM OPENJSON (@JSON,''$'') as jsonfile; 

		/*CHECK JSON FILE VALIDITY*/
		IF (ISJSON(@JSON)=1)
			
			SELECT 
				@p_jsonfile_key= jsonfile.[key]
			FROM OPENJSON (@JSON,''$'') as jsonfile;

			SELECT 
				@p_table_has_data= count(1)
			FROM vouchers
			WHERE stimulated_date=@p_jsonfile_key;

			/*CHECK DUPLICATE DATA*/
			IF @p_table_has_data=0 

				INSERT INTO vouchers 
									(
									STIMULATED_DATE	,
									USER_ID			,
									VOUCHER_CODE	,
									PRODUCT			,
									VENDOR_CATEGORY	,
									VENDOR			,
									STATUS
									)

				SELECT 
					main_value.[key] as STIMULATED_DATE										,
					JSON_VALUE(child_value.value, ''strict$.user_id'') AS USER_ID			,
					JSON_VALUE(child_value.value, ''strict$.voucher_code'') AS VOUCHER_CODE ,
					JSON_VALUE(child_value.value, ''strict$.product'') AS PRODUCT			,
					JSON_VALUE(child_value.value, ''strict$.vendor[0]'') AS VENDOR_CATEGORY ,
					JSON_VALUE(child_value.value, ''strict$.vendor[1]'') AS VENDOR			,
					JSON_VALUE(child_value.value, ''strict$.status'') AS STATUS    
				FROM OPENJSON(@JSON, ''$'') AS main_value
				CROSS APPLY OPENJSON (main_value.value, ''$'') as child_value'
		EXEC(@sqlquery)

		SET @begin_date = dateadd(dd,1,@begin_date);
	END
END
GO
