--------------------------------------------------------------
-- SETUP
-- This demo uses the Stack Overflow 2010 sample database
-- https://downloads.brentozar.com/StackOverflow2010.7z
-- We create a non-clustered index on the Posts table for this demo
-- Run via SSMS using the "Include Actual Execution Plan" for easy visualation of the query plans
--------------------------------------------------------------
USE [StackOverflow2010];
GO

CREATE NONCLUSTERED INDEX [IX_Posts_CommentCount] ON [dbo].[Posts]
(
	[CommentCount] ASC
);
GO

--------------------------------------------------------------
-- Intro
--------------------------------------------------------------
DBCC FREEPROCCACHE
SELECT AnswerCount FROM Posts WHERE CommentCount = 0;
-- High number of rows, scans the clustered index, uses parallelism

SELECT AnswerCount FROM Posts WHERE CommentCount = 27;
-- Low number of rows, seeks the non-clustered index, key lookup with a nested loop

--------------------------------------------------------------
-- Parameterize the query
--------------------------------------------------------------
DECLARE @p1 INT;
DECLARE @p2 INT;
DECLARE @p3 INT;
DECLARE @sql NVARCHAR(MAX) = N'SELECT AnswerCount FROM Posts WHERE CommentCount = @i';

EXEC sp_executesql @sql, N'@i INT', 0;
-- The parameter is sniffed, and the parallel execution plan is used

DBCC FREEPROCCACHE
EXEC sp_executesql @sql, N'@i INT', 27;
-- The parameter is sniffed, and the nested loop execution is used

DBCC FREEPROCCACHE
EXEC sp_executesql @sql, N'@i INT', 0;
-- The parameter is sniffed, and the parallel execution plan is used

EXEC sp_executesql @sql, N'@i INT', 27;
-- The parallel plan is reused, despite us knowing it is not the most optimal

DBCC FREEPROCCACHE
EXEC sp_prepare @p1 OUTPUT, N'@i INT', @sql;
EXEC sp_execute @p1, 0;
EXEC sp_unprepare @p1;
-- A new plan is being used. NCI seek, nested loop, with parallelism

DBCC FREEPROCCACHE
EXEC sp_prepare @p2 OUTPUT, N'@i INT', @sql;
EXEC sp_execute @p2, 27;
EXEC sp_unprepare @p2;
-- The same new plan is being used.

EXEC sp_prepare @p3 OUTPUT, N'@i INT', @sql;
EXEC sp_execute @p3, 0;
EXEC sp_unprepare @p3;
-- Reuses the plan as we haven't cleared the plan cache

EXEC sp_executesql @sql, N'@i INT', 27;
-- Interesting note - sp_executesql will also reuse the same plan!

--------------------------------------------------------------
-- Where is this plan coming from?
--------------------------------------------------------------
DECLARE @p INT;
SET @p = 0;
SELECT AnswerCount FROM Posts WHERE CommentCount = @p OPTION(OPTIMIZE FOR UNKNOWN);
SET @p = 27;
SELECT AnswerCount FROM Posts WHERE CommentCount = @p OPTION(OPTIMIZE FOR UNKNOWN);
-- It is the same plan as when we use the OPTIMIZE FOR UNKNOWN option
-- The estimated number of rows is 47810, whereas the actual number of rows is nearly 2M
-- Let's take a look at the statistics
-- 3729195 rows * 0.01282051 density vector = 47810
-- sp_prepexec uses the density vector estimate, rather than looking at the parameter.
-- For very linear distributions of data, this can be fine, but in almost all cases this can mean the plan
-- is never going to be suitable.

--------------------------------------------------------------
-- What can we do?
--------------------------------------------------------------
-- Add a covering index
CREATE NONCLUSTERED INDEX [IX_Posts_CommentCount_INCL_AnswerCount] ON [dbo].[Posts]
(
	[CommentCount] ASC
)
INCLUDE
(
	[AnswerCount]
);
GO

DBCC FREEPROCCACHE
DECLARE @p4 INT;
DECLARE @p5 INT;
DECLARE @sql NVARCHAR(MAX) = N'SELECT AnswerCount FROM Posts WHERE CommentCount = @i';
EXEC sp_executesql @sql, N'@i INT', 0;
DBCC FREEPROCCACHE
EXEC sp_executesql @sql, N'@i INT', 27;
DBCC FREEPROCCACHE
EXEC sp_prepare @p4 OUTPUT, N'@i INT', @sql;
EXEC sp_execute @p4, 0;
EXEC sp_unprepare @p4;
DBCC FREEPROCCACHE
EXEC sp_prepare @p5 OUTPUT, N'@i INT', @sql;
EXEC sp_execute @p5, 27;
EXEC sp_unprepare @p5;
-- These now all use the same best case plan each time

ALTER INDEX [IX_Posts_CommentCount_INCL_AnswerCount] ON [dbo].[Posts] DISABLE
GO
-- Disable the index so it cannot be used 

-- Create a stored procedure
CREATE OR ALTER PROC [dbo].[sp_demo_proc]
	@i INT
AS
SELECT AnswerCount FROM Posts WHERE CommentCount = @i
GO

DBCC FREEPROCCACHE;
EXEC sp_demo_proc @i = 0;

DBCC FREEPROCCACHE;
EXEC sp_demo_proc @i = 27;

DECLARE @p6 INT;
DECLARE @p7 INT;
DECLARE @sql NVARCHAR(MAX) = 'EXEC sp_demo_proc @i';
DECLARE @i INT = 0;

DBCC FREEPROCCACHE;
EXEC sp_prepare @p6 OUTPUT, N'@i INT', @sql;
EXEC sp_execute @p6, 0;
EXEC sp_unprepare @p6;

DBCC FREEPROCCACHE;
EXEC sp_prepare @p7 OUTPUT, N'@i INT', @sql;
EXEC sp_execute @p7, 27;
EXEC sp_unprepare @p7;
-- The parameter is sniffed and the best plan used in each case.
