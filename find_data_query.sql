DECLARE @SearchStrTableName nvarchar(255), @SearchStrColumnName nvarchar(255), @SearchStrColumnValue1 nvarchar(255), @SearchStrColumnValue2 nvarchar(255), @SearchStrInXML bit, @FullRowResult bit, @FullRowResultRows int
/* use LIKE Syntax */
SET @SearchStrColumnValue1 = '%test_string%' /* first value to search for */
SET @SearchStrColumnValue2 = NULL /* second value to search for, set NULL or empty if not used */
SET @FullRowResult = 1
SET @FullRowResultRows = 10 /* Update this value if you want to show more rows*/
SET @SearchStrTableName = NULL /* NULL for all tables, uses LIKE syntax */
SET @SearchStrColumnName = NULL /* NULL for all columns, uses LIKE syntax */
SET @SearchStrInXML = 0 /* Searching XML data may be slow */

IF OBJECT_ID('tempdb..#Results') IS NOT NULL DROP TABLE #Results
CREATE TABLE #Results (TableName nvarchar(128), ColumnName nvarchar(128), ColumnValue nvarchar(max), ColumnType nvarchar(20))

    SET NOCOUNT ON

DECLARE @TableName nvarchar(256) = '', @ColumnName nvarchar(128), @ColumnType nvarchar(20), @QuotedSearchStrColumnValue1 nvarchar(110), @QuotedSearchStrColumnValue2 nvarchar(110), @SearchCondition nvarchar(max)
SET @QuotedSearchStrColumnValue1 = QUOTENAME(@SearchStrColumnValue1,'''')
SET @QuotedSearchStrColumnValue2 = QUOTENAME(@SearchStrColumnValue2,'''')

DECLARE @ColumnNameTable TABLE (COLUMN_NAME nvarchar(128), DATA_TYPE nvarchar(20))

WHILE @TableName IS NOT NULL
BEGIN
    SET @TableName = 
    (
        SELECT MIN(QUOTENAME(TABLE_SCHEMA) + '.' + QUOTENAME(TABLE_NAME))
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_TYPE = 'BASE TABLE'
            AND TABLE_NAME LIKE COALESCE(@SearchStrTableName, TABLE_NAME)
            AND QUOTENAME(TABLE_SCHEMA) + '.' + QUOTENAME(TABLE_NAME) > @TableName
            AND OBJECTPROPERTY(OBJECT_ID(QUOTENAME(TABLE_SCHEMA) + '.' + QUOTENAME(TABLE_NAME)), 'IsMSShipped') = 0
    )
    IF @TableName IS NOT NULL
BEGIN
        DECLARE @sql VARCHAR(MAX)
        SET @sql = 'SELECT QUOTENAME(COLUMN_NAME), DATA_TYPE
                    FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = PARSENAME(''' + @TableName + ''', 2)
                    AND TABLE_NAME = PARSENAME(''' + @TableName + ''', 1)
                    AND DATA_TYPE IN (' + CASE WHEN ISNUMERIC(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@SearchStrColumnValue1,'%',''),'_',''),'[',''),']',''),'-','')) = 1 THEN '''tinyint'',''int'',''smallint'',''bigint'',''numeric'',''decimal'',''smallmoney'',''money'',' ELSE '' END + '''char'',''varchar'',''nchar'',''nvarchar'',''timestamp'',''uniqueidentifier''' + CASE @SearchStrInXML WHEN 1 THEN ',''xml''' ELSE '' END + ')
                    AND COLUMN_NAME LIKE COALESCE(' + CASE WHEN @SearchStrColumnName IS NULL THEN 'NULL' ELSE '''' + @SearchStrColumnName + '''' END  + ',COLUMN_NAME)'
        INSERT INTO @ColumnNameTable
        EXEC (@sql)
        WHILE EXISTS (SELECT TOP 1 COLUMN_NAME FROM @ColumnNameTable)
BEGIN
            PRINT @ColumnName
SELECT TOP 1 @ColumnName = COLUMN_NAME, @ColumnType = DATA_TYPE FROM @ColumnNameTable
    -- Build the search condition dynamically
    SET @SearchCondition = CASE @ColumnType 
                                    WHEN 'xml' THEN 'CAST(' + @ColumnName + ' AS nvarchar(MAX))'
                                    WHEN 'timestamp' THEN 'master.dbo.fn_varbintohexstr('+ @ColumnName + ')'
                                    ELSE @ColumnName
END + ' LIKE ' + @QuotedSearchStrColumnValue1
            IF @SearchStrColumnValue2 IS NOT NULL AND @SearchStrColumnValue2 <> ''
BEGIN
                SET @SearchCondition = @SearchCondition + ' OR ' + 
                                        CASE @ColumnType 
                                            WHEN 'xml' THEN 'CAST(' + @ColumnName + ' AS nvarchar(MAX))'
                                            WHEN 'timestamp' THEN 'master.dbo.fn_varbintohexstr('+ @ColumnName + ')'
                                            ELSE @ColumnName
END + ' LIKE ' + @QuotedSearchStrColumnValue2
END
            SET @sql = 'SELECT ''' + @TableName + ''',''' + @ColumnName + ''',' + 
                       CASE @ColumnType WHEN 'xml' THEN 'LEFT(CAST(' + @ColumnName + ' AS nvarchar(MAX)), 4096),''' 
                       WHEN 'timestamp' THEN 'master.dbo.fn_varbintohexstr('+ @ColumnName + '),'''
                       ELSE 'LEFT(' + @ColumnName + ', 4096),''' END + @ColumnType + ''' 
                       FROM ' + @TableName + ' (NOLOCK) ' +
                       ' WHERE ' + @SearchCondition
            INSERT INTO #Results
            EXEC(@sql)
            IF @@ROWCOUNT > 0 IF @FullRowResult = 1
BEGIN
                SET @sql = 'SELECT TOP ' + CAST(@FullRowResultRows AS VARCHAR(3)) + ' ''' + @TableName + ''' AS [TableFound],''' + @ColumnName + ''' AS [ColumnFound],''FullRow>'' AS [FullRow>],*' +
                           ' FROM ' + @TableName + ' (NOLOCK) ' +
                           ' WHERE ' + @SearchCondition
                EXEC(@sql)
END
DELETE FROM @ColumnNameTable WHERE COLUMN_NAME = @ColumnName
END
END
END
SET NOCOUNT OFF

SELECT TableName, ColumnName, ColumnValue, ColumnType, COUNT(*) AS Count FROM #Results
GROUP BY TableName, ColumnName, ColumnValue, ColumnType
