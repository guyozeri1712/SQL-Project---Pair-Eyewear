--דרופים רלוונטים כדי לוודא שכל הקוד רץ, לא רלוונטי אם זאת הרצה ראשונה של הקוד
DROP INDEX IF EXISTS IX_Orders_Date ON Orders
DROP INDEX IF EXISTS IX_Ordered_Product ON Ordered
DROP INDEX IF EXISTS IX_Glasses_Ordered_Product ON Glasses_Ordered
DROP INDEX IF EXISTS IX_CreditCards_Customer ON CREDIT_CARDS
DROP INDEX IF EXISTS IX_Orders_CardNumber ON ORDERS
DROP INDEX IF EXISTS IX_Ordered_Order ON ORDERED
DROP INDEX IF EXISTS IX_GlassesOrdered_Order ON GLASSES_ORDERED
DROP INDEX IF EXISTS IX_Selected ON SELECTED
DROP INDEX IF EXISTS IX_Customizations ON CUSTOMIZATIONS
DROP VIEW IF EXISTS PRODUCTS_OVERVIEW
DROP FUNCTION IF EXISTS GetRatingGap
DROP FUNCTION IF EXISTS GetCustomerHistory
DROP TRIGGER IF EXISTS UpdateAmountOrderableProducts
DROP TRIGGER IF EXISTS UpdateAmountGlasses
DROP PROCEDURE IF EXISTS ApplyDiscountsOnLowSellingProducts
DROP VIEW IF EXISTS Product_Annual_Stats
DROP VIEW IF EXISTS Revenue_By_Year
ALTER TABLE ORDERS DROP CONSTRAINT DF_ORDERS_Total_Amount
ALTER TABLE ORDERS DROP COLUMN IF EXISTS Total_Amount
ALTER TABLE PRODUCTS DROP COLUMN IF EXISTS Discount
DROP TABLE IF EXISTS EmailErrorLog 
DROP PROCEDURE IF EXISTS AddCustomerWithEmailValidation







--פרק ראשון




--מטלה 1




--שאילתות ללא קינון


--שאילתה מס' 1
SELECT DISTINCT C.Customer_ID, SUM(P.Price*G_O.Units +ISNULL(CS.Extra_Price, 0)) AS TC
FROM ORDERS O JOIN CREDIT_CARDS CC ON O.Card_Number = CC.Card_Number
              JOIN CUSTOMERS C ON C.Customer_ID=CC.Customer_ID
                	  JOIN GLASSES_ORDERED G_O ON G_O.Order_ID=O.Order_ID
                	  JOIN PRODUCTS P ON G_O.Product_ID=P.Product_ID
                	  JOIN VERSIONS V ON V.Product_ID=P.Product_ID AND G_O.[Version] =V.[Version]
                	  JOIN SELECTED S ON S.[Version] =V.[Version] AND S.Product_ID =V.Product_ID
                	  JOIN CUSTOMIZATIONS CS ON CS.Feature=S.Feature AND S.Selection = CS.Selection
WHERE DATEDIFF(YEAR, O.Date,GETDATE()) <=3
GROUP BY C.Customer_ID, C.First_Name, c.Last_Name
HAVING SUM(G_O.Units*P.Price)>2000
ORDER BY TC

--שאילתה מס' 2
SELECT TOP 10 P.Name, Amount = SUM(ISNULL(O.Units, 0) + ISNULL(G.Units, 0))
FROM Products AS P
LEFT JOIN Ordered AS O ON P.Product_ID = O.Product_ID
LEFT JOIN Orders AS Ord1 ON O.Order_ID = Ord1.Order_ID
LEFT JOIN Glasses_Ordered AS G ON P.Product_ID = G.Product_ID
LEFT JOIN Orders AS Ord2 ON G.Order_ID = Ord2.Order_ID
WHERE (YEAR(Ord1.[Date]) = 2025 OR YEAR(Ord2.[Date]) = 2025)
GROUP BY P.Name
ORDER BY Amount DESC


--שאילתות עם קינון


--שאילתה מס' 1
SELECT DISTINCT P.Product_ID, P.Name
FROM	PRODUCTS AS P JOIN SEARCHES_FOR_PRODUCTS AS SFP ON P.Product_ID = 
SFP.Product_ID
WHERE P.Product_ID NOT IN (
	SELECT Product_ID FROM ORDERED
	UNION
	SELECT Product_ID FROM GLASSES_ORDERED )


--שאילתה מס' 2
SELECT DISTINCT C.Customer_ID, [Full Name]= c.First_Name+' '+C.Last_Name
FROM CUSTOMERS C JOIN REVIEWS R ON R.Customer_ID=C.Customer_ID
WHERE  R.Rating < ( SELECT  AVG(R1.Rating)
                    FROM REVIEWS R1
                    WHERE R1.Product_ID = R.Product_ID )


--שאילתות עם פונקציית חלון


--שאילתה מס' 1
SELECT
	Year,
	Quarter,
	Quarterly_Revenue = SUM(Revenue),
	Quarter_Rank = RANK() OVER (PARTITION BY Year ORDER BY SUM(Revenue) 
DESC),
	Same_Quarter_Last_Year =
    	LAG(SUM(Revenue)) OVER (PARTITION BY Quarter ORDER BY Year),
	Revenue_Change =
    	SUM(Revenue) - LAG(SUM(Revenue)) OVER (PARTITION BY Quarter ORDER BY 
Year)
FROM (
	-- Regular product orders
	SELECT
    	YEAR(ord.Date) AS Year,
    	DATEPART(QUARTER, ord.Date) AS Quarter,
    	Revenue = o.Units * p.Price
	FROM ORDERS ord
	JOIN ORDERED o ON ord.Order_ID = o.Order_ID
	JOIN PRODUCTS p ON o.Product_ID = p.Product_ID
 
	UNION ALL
 
	-- Customized glasses orders
	SELECT
    	YEAR(ord.Date) AS Year,
    	DATEPART(QUARTER, ord.Date) AS Quarter,
    	Revenue = g.Units * vp.Total_Price
	FROM ORDERS ord
	JOIN GLASSES_ORDERED g ON ord.Order_ID = g.Order_ID
	JOIN (
    	-- A table of each glasses's version and it's price
    	SELECT
        	v.Product_ID,
        	v.Version,
        	Total_Price = p.Price + ISNULL(SUM(c.Extra_Price), 0)
    	FROM VERSIONS v
    	JOIN PRODUCTS p ON v.Product_ID = p.Product_ID
    	LEFT JOIN SELECTED s ON v.Product_ID = s.Product_ID AND v.Version = 
s.Version
    	LEFT JOIN CUSTOMIZATIONS c ON s.Feature = c.Feature AND s.Selection = 
c.Selection
    	GROUP BY v.Product_ID, v.Version, p.Price
	) AS vp ON g.Product_ID = vp.Product_ID AND g.Version = vp.Version
) AS All_Revenue
WHERE Year >= YEAR(GETDATE()) - 5
GROUP BY Year, Quarter
ORDER BY Year DESC, Quarter_Rank


--שאילתה מס' 2
SELECT *
FROM (
  SELECT  C.Customer_ID, C.First_Name + ' ' + C.Last_Name AS Full_Name,
   	COUNT(DISTINCT S.DT) AS Number_Of_Searches,
   	COUNT(DISTINCT O.Order_ID) AS Number_Of_Orders,
   	CAST(ROUND(1.0 * COUNT(DISTINCT S.DT) / NULLIF(COUNT(DISTINCT 
O.Order_ID), 0), 3) AS DECIMAL(10,3)) AS Ratio,         	-- חישוב היחס בין מספר החיפושים למספר ההזמנות
   	NTILE(4) OVER ( ORDER BY 1.0 * COUNT(DISTINCT S.DT) / 
NULLIF(COUNT(DISTINCT O.Order_ID), 0) DESC ) AS Quartile , -- חלוקת הלקוחות ל 4 רביעים בהתאם ליחס חיפוש-רכישה שלהם
   	 ( SELECT AVG(DATEDIFF(DAY, Prev_Search_Date, Search_Date)) -- חישוב ממוצע בין חיפושי הלקוח
   	FROM (
    	SELECT  S1.DT AS Search_Date,
           	LAG(S1.DT) OVER (PARTITION BY S1.Customer_ID ORDER BY S1.DT) AS 
Prev_Search_Date -- תאריך הזמנה קודם של לקוח
    	FROM SEARCHES S1
    	WHERE S1.Customer_ID = C.Customer_ID
   	) AS Gaps
   	WHERE Prev_Search_Date IS NOT NULL
   	) AS Avg_Days_Between_Searches
 
  FROM CUSTOMERS C
  LEFT JOIN SEARCHES S ON C.Customer_ID = S.Customer_ID
  LEFT JOIN CREDIT_CARDS CC ON C.Customer_ID = CC.Customer_ID
  LEFT JOIN ORDERS O ON O.Card_Number = CC.Card_Number
  GROUP BY C.Customer_ID, C.First_Name, C.Last_Name
) AS T
WHERE Quartile = 1
ORDER BY Ratio DESC;


--שאילתה עם פסקת WITH
WITH
ORDER_INTERVALS AS (
	SELECT
   	Country,
   	Order_Date = O.[Date],
   	Prev_Order_Date = LAG(O.[Date]) OVER (PARTITION BY Country ORDER BY 
O.[Date]),
   	Days_Since_Last_Order = DATEDIFF(DAY,
       	LAG(O.[Date]) OVER (PARTITION BY Country ORDER BY O.[Date]),
       	O.[Date])
	FROM ORDERS O
),
AVG_INTERVALS AS (
	SELECT
   	Country,
   	Avg_Days_Between_Orders = AVG(Days_Since_Last_Order * 1.0)
	FROM ORDER_INTERVALS
	WHERE Days_Since_Last_Order IS NOT NULL
	GROUP BY Country
),
CUSTOMER_COUNTS AS (
	SELECT
   	O.Country,
   	Active_Customers = COUNT(DISTINCT CC.Customer_ID),
   	Total_Orders = COUNT(DISTINCT O.Order_ID)
	FROM ORDERS O
	JOIN CREDIT_CARDS CC ON O.Card_Number = CC.Card_Number
	GROUP BY O.Country
),
Version_Prices AS (
	SELECT
      	V.Product_ID,
      	V.Version,
      	Total_Price = P.Price + ISNULL((
            	SELECT SUM(C.Extra_Price)
            	FROM SELECTED S
            	JOIN CUSTOMIZATIONS C ON S.Feature = C.Feature AND 
S.Selection = C.Selection
            	WHERE S.Product_ID = V.Product_ID AND S.Version = V.Version
      	), 0)
	FROM VERSIONS V
	JOIN PRODUCTS P ON V.Product_ID = P.Product_ID
),
REVENUE_BY_COUNTRY AS (
	SELECT
   	O.Country,
   	Total_Revenue =
       	ISNULL(SUM(OD.D_Revenue), 0) + ISNULL(SUM(OG.G_Revenue), 0)
	FROM ORDERS O
	LEFT JOIN (
    	SELECT
        	D.Order_ID,
        	SUM(D.Units * P.Price) AS D_Revenue
    	FROM ORDERED D
    	JOIN PRODUCTS P ON D.Product_ID = P.Product_ID
    	GROUP BY D.Order_ID
	) AS OD ON O.Order_ID = OD.Order_ID
	LEFT JOIN (
    	SELECT
        	G.Order_ID,
        	SUM(G.Units * VP.Total_Price) AS G_Revenue
    	FROM GLASSES_ORDERED G
    	JOIN Version_Prices VP ON G.Product_ID = VP.Product_ID AND G.Version = 
VP.Version
    	GROUP BY G.Order_ID
	) AS OG ON O.Order_ID = OG.Order_ID
	GROUP BY O.Country
),
COMBINED_STATS AS (
	SELECT
   	A.Country,
   	Avg_Days_Between_Orders,
   	C.Active_Customers,
   	C.Total_Orders,
   	R.Total_Revenue,
   	Revenue_Share = R.Total_Revenue * 1.0 / SUM(R.Total_Revenue) OVER(),
   	Efficiency = R.Total_Revenue * 1.0 / NULLIF(A.Avg_Days_Between_Orders, 0)
	FROM AVG_INTERVALS A
	JOIN CUSTOMER_COUNTS C ON A.Country = C.Country
	JOIN REVENUE_BY_COUNTRY R ON A.Country = R.Country
)
SELECT
	Country,
	CAST(Avg_Days_Between_Orders AS DECIMAL(10,2)) AS 
Avg_Days_Between_Orders,
	Active_Customers,
	Total_Orders,
	CAST(Total_Revenue AS DECIMAL(12,2)) AS Total_Revenue,
	CAST(Revenue_Share AS DECIMAL(5,4)) AS Revenue_Share,
	CAST(Efficiency AS DECIMAL(12,2)) AS Efficiency
FROM COMBINED_STATS
ORDER BY Efficiency DESC;

GO
--מטלה 2


--VIEW

--יצירה
CREATE VIEW PRODUCTS_OVERVIEW AS
SELECT
   	P.Product_ID,
   	P.Name,
   	-- Rating
   	Rating = ISNULL(ROUND(AVG(CAST(R.Rating AS FLOAT)), 2), 0),
   	-- Search count & order count
   	Total_Searches = ISNULL(SC.Total_Searches, 0),
   	Total_Orders = ISNULL(OC.Total_Orders, 0),
   	-- Search to order ratio
  	 Search_Order_Ratio =
      		ROUND (CASE                           	  	
                   	 	WHEN ISNULL(OC.Total_Orders, 0) = 0 THEN 0
                   	 	WHEN ISNULL(SC.Total_Searches, 0) = 0 THEN 0
                   	 	ELSE CAST(OC.Total_Orders AS FLOAT) /
						SC.Total_Searches
             		END,
      		3),
   	-- Avg days between orders
   	Avg_Days_Between_Orders =
             		CAST((
             		SELECT AVG(DATEDIFF(DAY, PrevOrder, CurrOrder) * 1.0)
             		FROM ( SELECT
                          	O.Date AS CurrOrder,
                          	LAG(O.Date) OVER (ORDER BY O.Date ASC) AS
PrevOrder
                   	 	FROM ORDERS O
                   	 	WHERE O.Order_ID IN (
                          		SELECT Order_ID FROM ORDERED WHERE
Product_ID = P.Product_ID
                          	UNION
                          		SELECT Order_ID FROM GLASSES_ORDERED
WHERE Product_ID = P.Product_ID
                   	 	)
             		) AS Gaps
             		WHERE PrevOrder IS NOT NULL
             		) AS DECIMAL(10,2)),
   	
   	-- Total units
   	Total_Units = ISNULL((
	   SELECT SUM(Units)
	   FROM (
    	  	SELECT Units FROM ORDERED WHERE Product_ID = P.Product_ID
    	  	UNION ALL
    	  	SELECT Units FROM GLASSES_ORDERED WHERE Product_ID = P.Product_ID
	   ) AS AllUnits
   	), 0),
 
   	-- Top country
   	Top_Country =
      		 (
             		SELECT TOP 1 O.Country
             		FROM (
                   	 	SELECT Order_ID
FROM ORDERED
WHERE Product_ID = P.Product_ID
                   	 	UNION ALL
                   	 	SELECT Order_ID
FROM GLASSES_ORDERED
WHERE Product_ID = P.Product_ID
             		) AS OrdersList
             		JOIN ORDERS O ON OrdersList.Order_ID = O.Order_ID
             		GROUP BY O.Country
             		ORDER BY COUNT(*) DESC)      		
FROM PRODUCTS P
 
-- Ratings
LEFT JOIN REVIEWS R ON P.Product_ID = R.Product_ID
 
-- Precomputed search count per product
LEFT JOIN (
   	SELECT Product_ID, Total_Searches = COUNT(*)
   	FROM SEARCHES_FOR_PRODUCTS
   	GROUP BY Product_ID
) SC ON SC.Product_ID = P.Product_ID
 
-- Precomputed orders count per product
LEFT JOIN (
   	SELECT Product_ID, Total_Orders = COUNT(*)
   	FROM (
	   SELECT Product_ID, Order_ID FROM ORDERED
	   UNION ALL
	   SELECT Product_ID, Order_ID FROM GLASSES_ORDERED
   	) AS AllOrders
   	GROUP BY Product_ID
) OC ON OC.Product_ID = P.Product_ID
 
GROUP BY P.Product_ID, P.Name, SC.Total_Searches, OC.Total_Orders

GO
--פלט כללי
SELECT *
FROM PRODUCTS_OVERVIEW

--דוגמא לשימוש
SELECT TOP 10 Product_ID, Name, Rating, Total_Orders, Top_Country
FROM PRODUCTS_OVERVIEW
ORDER BY Rating DESC;

GO

-- פונקציות

--פונקציה מס' 1

--יצירה
CREATE FUNCTION GetRatingGap(@Review_ID INT)
RETURNS FLOAT
AS
BEGIN
   	DECLARE @Result FLOAT
   	SET @Result = ( SELECT R.Rating - PO.Rating
                	    FROM PRODUCTS_OVERVIEW AS PO JOIN REVIEWS AS R ON 
PO.Product_ID = R.Product_ID
                      WHERE R.Review_ID = @Review_ID )
   	RETURN @Result
END
GO

--דוגמא לשימוש
SELECT *, Gap = dbo.GetRatingGap(Review_ID)
FROM REVIEWS
WHERE YEAR(Date) = YEAR(GetDate()) AND dbo.GetRatingGap(Review_ID) < -2

GO

--פונקציה מס' 2

--יצירה
CREATE FUNCTION GetCustomerHistory (@CustomerID INT)
RETURNS TABLE
AS
RETURN (
	WITH Version_Prices AS (
    	SELECT
        	V.Product_ID,
        	V.Version,
        	P.Price + ISNULL(SUM(C.Extra_Price), 0) AS Total_Price
    	FROM VERSIONS V
    	JOIN BASE_FRAMES BF ON V.Product_ID = BF.Product_ID
    	JOIN PRODUCTS P ON BF.Product_ID = P.Product_ID
    	LEFT JOIN SELECTED S ON V.Product_ID = S.Product_ID AND V.Version = 
S.Version
    	LEFT JOIN CUSTOMIZATIONS C ON S.Feature = C.Feature AND S.Selection = 
C.Selection
    	GROUP BY V.Product_ID, V.Version, P.Price
	),
	Ordered_Summary AS (
    	SELECT
        	O.Order_ID,
        	SUM(ISNULL(D.Units, 0)) AS Units_Ordered,
        	SUM(ISNULL(D.Units * P.Price, 0)) AS Cost_Ordered
    	FROM ORDERS O
    	JOIN ORDERED D ON O.Order_ID = D.Order_ID
    	JOIN PRODUCTS P ON D.Product_ID = P.Product_ID
    	GROUP BY O.Order_ID
	),
	Glasses_Summary AS (
    	SELECT
        	O.Order_ID,
        	SUM(ISNULL(G.Units, 0)) AS Units_Glasses,
        	SUM(ISNULL(G.Units * VP.Total_Price, 0)) AS Cost_Glasses
    	FROM ORDERS O
    	JOIN GLASSES_ORDERED G ON O.Order_ID = G.Order_ID
    	JOIN Version_Prices VP ON G.Product_ID = VP.Product_ID AND G.Version = 
VP.Version
    	GROUP BY O.Order_ID
	)
	SELECT
    	O.Order_ID,
    	O.[Date],
    	Total_Units =
        	ISNULL(OS.Units_Ordered, 0) + ISNULL(GS.Units_Glasses, 0),
    	Total_Cost =
        	ISNULL(OS.Cost_Ordered, 0) + ISNULL(GS.Cost_Glasses, 0)
	FROM CREDIT_CARDS CC
	JOIN ORDERS O ON CC.Card_Number = O.Card_Number
	LEFT JOIN Ordered_Summary OS ON O.Order_ID = OS.Order_ID
	LEFT JOIN Glasses_Summary GS ON O.Order_ID = GS.Order_ID
	WHERE CC.Customer_ID = @CustomerID
)
GO
--דוגמא לשימוש
SELECT *
FROM dbo.GetCustomerHistory(3)


--TRIGGER

--יצירת שדה מחושב בטבלת הזמנות
ALTER TABLE ORDERS
ADD Total_Amount DECIMAL(10,2)
CONSTRAINT DF_ORDERS_Total_Amount DEFAULT 0 WITH VALUES;
GO

--עדכון ערך השדה המחושב
UPDATE ORDERS
SET Total_Amount =
	ISNULL(RP.Total_Regular, 0) + ISNULL(GO.Total_Glasses, 0)
FROM ORDERS
LEFT JOIN (
	SELECT
    	ORDERED.Order_ID,
    	SUM(ORDERED.Units * PRODUCTS.Price) AS Total_Regular
	FROM ORDERED
	JOIN PRODUCTS ON ORDERED.Product_ID = PRODUCTS.Product_ID
	GROUP BY ORDERED.Order_ID
) RP ON ORDERS.Order_ID = RP.Order_ID
LEFT JOIN (
	SELECT
    	GLASSES_ORDERED.Order_ID,
    	SUM(GLASSES_ORDERED.Units * (PRODUCTS.Price + ISNULL(C.Extra_Total, 
0))) AS Total_Glasses
	FROM GLASSES_ORDERED
	JOIN PRODUCTS ON GLASSES_ORDERED.Product_ID = PRODUCTS.Product_ID
	LEFT JOIN (
    	SELECT
        	SELECTED.Product_ID,
        	SELECTED.Version,
        	SUM(CUSTOMIZATIONS.Extra_Price) AS Extra_Total
    	FROM SELECTED
    	JOIN CUSTOMIZATIONS ON SELECTED.Feature = CUSTOMIZATIONS.Feature
                        	AND 	SELECTED.Selection = 
CUSTOMIZATIONS.Selection
    	GROUP BY SELECTED.Product_ID, SELECTED.Version
	) C ON GLASSES_ORDERED.Product_ID = C.Product_ID AND 
GLASSES_ORDERED.Version = C.Version
	GROUP BY GLASSES_ORDERED.Order_ID
) GO ON ORDERS.Order_ID = GO.Order_ID

GO

-- ORDERED כתיבת טריגר
CREATE TRIGGER UpdateAmountOrderableProducts
ON ORDERED
AFTER INSERT, DELETE
AS
BEGIN
	-- במידה ומתבצעות הוספת רשומות
	IF EXISTS (SELECT * FROM INSERTED)
	BEGIN
        UPDATE O
        SET O.Total_Amount = O.Total_Amount + X.TotalPrice
        FROM ORDERS O
        JOIN (
            SELECT I.Order_ID, SUM(I.Units * P.Price) AS TotalPrice
            FROM INSERTED I
            JOIN PRODUCTS P ON I.Product_ID = P.Product_ID
            GROUP BY I.Order_ID
        ) AS X ON O.Order_ID = X.Order_ID
	END
 
	-- במידה ומתבצעות מחיקת רשומות
	IF EXISTS (SELECT * FROM DELETED)
	BEGIN
        UPDATE O
        SET O.Total_Amount = O.Total_Amount - X.TotalPrice
        FROM ORDERS O
        JOIN (
            SELECT D.Order_ID, SUM(D.Units * P.Price) AS TotalPrice
            FROM DELETED D
            JOIN PRODUCTS P ON D.Product_ID = P.Product_ID
            GROUP BY D.Order_ID
        ) AS X ON O.Order_ID = X.Order_ID
	END
END


GO

-- GLASSES_ORDERED כתיבת טריגר
CREATE TRIGGER UpdateAmountGlasses
ON GLASSES_ORDERED
FOR INSERT, DELETE
AS
BEGIN
	-- במידה ומתבצעות הוספת רשומות
	IF EXISTS (SELECT * FROM INSERTED)
	BEGIN
        WITH ExtraPerUnit AS (
            SELECT
            	I.Order_ID,
            	I.Product_ID,
            	I.Version,
            	SUM(ISNULL(CS.Extra_Price, 0)) AS Extra
            FROM INSERTED I
            JOIN VERSIONS V ON V.Product_ID = I.Product_ID AND V.Version = 
I.Version
            JOIN SELECTED S ON S.Product_ID = V.Product_ID AND S.Version = 
V.Version
            JOIN CUSTOMIZATIONS CS ON CS.Feature = S.Feature AND CS.Selection 
= S.Selection
            GROUP BY I.Order_ID, I.Product_ID, I.Version
        )
 
        UPDATE O
        SET O.Total_Amount = ISNULL(O.Total_Amount, 0) + X.TotalPrice
        FROM ORDERS O
        JOIN (
            SELECT
            	I.Order_ID,
            	SUM(I.Units * (P.Price + ISNULL(E.Extra, 0))) AS TotalPrice
            FROM INSERTED I
            JOIN PRODUCTS P ON I.Product_ID = P.Product_ID
            LEFT JOIN ExtraPerUnit E ON I.Order_ID = E.Order_ID AND 
I.Product_ID = E.Product_ID AND I.Version = E.Version
            GROUP BY I.Order_ID
        ) AS X ON O.Order_ID = X.Order_ID;
	END
 
        -- במידה ומתבצעות מחיקת רשומות
	IF EXISTS (SELECT * FROM DELETED)
	BEGIN
        WITH ExtraPerUnit AS (
            SELECT
            	D.Order_ID,
            	D.Product_ID,
            	D.Version,
            	SUM(ISNULL(CS.Extra_Price, 0)) AS Extra
            FROM DELETED D
            JOIN VERSIONS V ON V.Product_ID = D.Product_ID AND V.Version = 
D.Version
            JOIN SELECTED S ON S.Product_ID = V.Product_ID AND S.Version = 
V.Version
            JOIN CUSTOMIZATIONS CS ON CS.Feature = S.Feature AND CS.Selection 
= S.Selection
           GROUP BY D.Order_ID, D.Product_ID, D.Version
        )
 
        UPDATE O
        SET O.Total_Amount = ISNULL(O.Total_Amount, 0) - X.TotalPrice
        FROM ORDERS O
        JOIN (
            SELECT
            	D.Order_ID,
            	SUM(D.Units * (P.Price + ISNULL(E.Extra, 0))) AS TotalPrice
            FROM DELETED D
            JOIN PRODUCTS P ON D.Product_ID = P.Product_ID
            LEFT JOIN ExtraPerUnit E ON D.Order_ID = E.Order_ID AND 
D.Product_ID = E.Product_ID AND D.Version = E.Version
            GROUP BY D.Order_ID
        ) AS X ON O.Order_ID = X.Order_ID;
	END
END

--דוגמא לשימוש
DELETE FROM GLASSES_ORDERED
WHERE Product_ID = 14
  AND Version = 1
  AND Order_ID = (
  	SELECT TOP 1 O.Order_ID
  	FROM ORDERS O
  	JOIN CREDIT_CARDS CC ON O.Card_Number = CC.Card_Number
  	WHERE CC.Customer_ID = (
      	SELECT Customer_ID
      	FROM CUSTOMERS
      	WHERE Email = 'michael.martinez14@outlook.org'
  	)
  	ORDER BY O.Date DESC
)

GO

--פרוצדורה שמורה

--הוספת שדה מתאים בטבלת מוצרים
ALTER TABLE PRODUCTS ADD Discount Float;

GO

--יצירת הפרוצדורה
CREATE PROCEDURE ApplyDiscountsOnLowSellingProducts
    @StartDate DATE,
    @EndDate DATE,
    @LowerDiscount FLOAT,
    @UpperDiscount FLOAT
AS
BEGIN
	-- עדכון זמני של כל המוצרים לפי יחס דירוג למכירות
	WITH ProductStats AS (
        SELECT
            P.Product_ID,
            AVG(CAST(R.Rating AS FLOAT)) AS AvgRating,
            ISNULL(SUM(O.Units), 0) AS TotalUnits,
            DATEDIFF(DAY, MAX(Ors.Date), GETDATE()) AS DaysSinceLastOrder
        FROM PRODUCTS P
        LEFT JOIN REVIEWS R ON P.Product_ID = R.Product_ID
        LEFT JOIN ORDERED O ON P.Product_ID = O.Product_ID
        LEFT JOIN ORDERS Ors ON O.Order_ID = Ors.Order_ID
        GROUP BY P.Product_ID
	),
    RankedStats AS (
        SELECT *,
            -- מחשבים את המקסימום והטווח
            MAX(CASE WHEN TotalUnits = 0 THEN AvgRating ELSE AvgRating / TotalUnits END)
            	OVER() AS MaxRatio,
            MIN(CASE WHEN TotalUnits = 0 THEN AvgRating ELSE AvgRating / TotalUnits END)
            	OVER() AS MinRatio
        FROM ProductStats
        WHERE DaysSinceLastOrder >= 150 OR DaysSinceLastOrder IS NULL
	)
	UPDATE P
	SET Discount = ROUND( 
        CASE
            WHEN RS.MaxRatio = RS.MinRatio THEN @UpperDiscount -- להימנע מחלוקה ב־0
            ELSE @LowerDiscount +
             	((CASE WHEN RS.TotalUnits = 0 THEN RS.AvgRating ELSE RS.AvgRating / RS.TotalUnits END - RS.MinRatio)
              	/ NULLIF(RS.MaxRatio - RS.MinRatio, 0))
             	* (@UpperDiscount - @LowerDiscount)
        END ,2)
	FROM PRODUCTS P
	JOIN RankedStats RS ON P.Product_ID = RS.Product_ID
END

--דוגמא לשימוש
EXEC ApplyDiscountsOnLowSellingProducts
 	@StartDate = '2025-06-01',
     @EndDate = '2025-06-30',
     @LowerDiscount = 0.1,
     @UpperDiscount = 0.5;

GO


--מטלה 3


-- שיצרנו VIEWS

-- 1 VIEW

CREATE VIEW Product_Annual_Stats AS
SELECT
	P.Product_ID,
	P.Name,
	Y.Year,
	
	-- Total Searches
	ISNULL((
    	SELECT COUNT(*)
    	FROM SEARCHES_FOR_PRODUCTS S
    	WHERE S.Product_ID = P.Product_ID AND YEAR(S.DT) = Y.Year
	), 0) AS Total_Searches,
	
	-- Total Orders
	ISNULL((
    	SELECT COUNT(DISTINCT O1.Order_ID)
    	FROM ORDERED O1
    	JOIN ORDERS OR1 ON O1.Order_ID = OR1.Order_ID
    	WHERE O1.Product_ID = P.Product_ID AND YEAR(OR1.Date) = Y.Year
	), 0)
	+
	ISNULL((
    	SELECT COUNT(DISTINCT G1.Order_ID)
    	FROM GLASSES_ORDERED G1
    	JOIN ORDERS OR2 ON G1.Order_ID = OR2.Order_ID
    	WHERE G1.Product_ID = P.Product_ID AND YEAR(OR2.Date) = Y.Year
	), 0) AS Total_Orders,
 
	-- Total Units Sold
	ISNULL((
    	SELECT SUM(O2.Units)
    	FROM ORDERED O2
    	JOIN ORDERS OR3 ON O2.Order_ID = OR3.Order_ID
    	WHERE O2.Product_ID = P.Product_ID AND YEAR(OR3.Date) = Y.Year
	), 0)
	+
	ISNULL((
    	SELECT SUM(G2.Units)
    	FROM GLASSES_ORDERED G2
    	JOIN ORDERS OR4 ON G2.Order_ID = OR4.Order_ID
    	WHERE G2.Product_ID = P.Product_ID AND YEAR(OR4.Date) = Y.Year
	), 0) AS Total_Units_Sold,
 
	--  Rating
	CAST((
    	SELECT AVG(CAST(R.Rating AS FLOAT))
    	FROM REVIEWS R
    	WHERE R.Product_ID = P.Product_ID AND YEAR(R.Date) = Y.Year
	) AS DECIMAL(4,2)) AS Rating
 
FROM PRODUCTS P
CROSS JOIN (SELECT 2023 AS Year UNION ALL SELECT 2024 UNION ALL SELECT 2025) AS Y

GO

-- 2 VIEW
CREATE VIEW Revenue_By_Year AS
SELECT
	Year,
	Total_Revenue,
	Revenue_Target = ROUND(LAG(Total_Revenue) OVER (ORDER BY Year) * 1.3, 
0)
FROM (
	SELECT
    	YEAR([Date]) AS Year,
    	SUM(Total_Amount) AS Total_Revenue
	FROM ORDERS
	GROUP BY YEAR([Date])
) AS YearlyRevenue


GO


--מטלה 4


--אופטימיזציה מס' 1

--יצירת אינדקסים
CREATE INDEX IX_Orders_Date ON Orders([Date], Order_ID);
CREATE INDEX IX_Ordered_Product ON Ordered(Product_ID, Order_ID, Units);
CREATE INDEX IX_Glasses_Ordered_Product ON Glasses_Ordered(Product_ID, Order_ID, Units);

GO

--שינוי השאילתה
SELECT TOP 10 P.Name, SUM(X.Units) AS Amount
FROM Products AS P
INNER JOIN (
	SELECT O.Product_ID, O.Units
	FROM Ordered O
	INNER JOIN Orders Ord ON O.Order_ID = Ord.Order_ID
	WHERE Ord.[Date] >= '2025-01-01' AND Ord.[Date] < '2026-01-01'
 
	UNION ALL
 
	SELECT G.Product_ID, G.Units
	FROM Glasses_Ordered G
	INNER JOIN Orders Ord ON G.Order_ID = Ord.Order_ID
	WHERE Ord.[Date] >= '2025-01-01' AND Ord.[Date] < '2026-01-01'
) AS X ON P.Product_ID = X.Product_ID
GROUP BY P.Name
ORDER BY Amount DESC;

GO

--אופטימיזציה מס' 2

--יצירת אינדקסים
CREATE INDEX IX_CreditCards_Customer ON CREDIT_CARDS(Customer_ID, Card_Number);
CREATE INDEX IX_Orders_CardNumber ON ORDERS(Card_Number, Order_ID, [Date]);
CREATE INDEX IX_Ordered_Order ON ORDERED(Order_ID, Product_ID, Units);
CREATE INDEX IX_GlassesOrdered_Order ON GLASSES_ORDERED(Order_ID, Product_ID, Version, Units);
CREATE INDEX IX_Selected ON SELECTED(Product_ID, Version, Feature, Selection);
CREATE INDEX IX_Customizations ON CUSTOMIZATIONS(Feature, Selection, Extra_Price);

GO

--מחיקת הפונקציה הקיימת
DROP FUNCTION IF EXISTS GetCustomerHistory
GO


--יצירת הפונקציה החדשה
CREATE FUNCTION GetCustomerHistory (@CustomerID INT)
RETURNS TABLE
AS
RETURN
(
	WITH Customer_Orders AS (
    	SELECT O.Order_ID, O.[Date]
    	FROM ORDERS O
    	INNER JOIN CREDIT_CARDS CC
        	ON O.Card_Number = CC.Card_Number
    	WHERE CC.Customer_ID = @CustomerID
	),
	Version_Prices AS (
    	SELECT
        	V.Product_ID,
        	V.Version,
        	P.Price + ISNULL(SUM(C.Extra_Price), 0) AS Total_Price
    	FROM VERSIONS V
    	INNER JOIN BASE_FRAMES BF
        	ON V.Product_ID = BF.Product_ID
    	INNER JOIN PRODUCTS P
        	ON BF.Product_ID = P.Product_ID
    	LEFT JOIN SELECTED S
        	ON V.Product_ID = S.Product_ID AND V.Version = S.Version
    	LEFT JOIN CUSTOMIZATIONS C
        	ON S.Feature = C.Feature AND S.Selection = C.Selection
    	GROUP BY V.Product_ID, V.Version, P.Price
	),
	Ordered_Summary AS (
    	SELECT
        	O.Order_ID,
        	SUM(D.Units) AS Units_Ordered,
        	SUM(D.Units * P.Price) AS Cost_Ordered
    	FROM Customer_Orders O
    	INNER JOIN ORDERED D
        	ON O.Order_ID = D.Order_ID
    	INNER JOIN PRODUCTS P
        	ON D.Product_ID = P.Product_ID
    	GROUP BY O.Order_ID
	),
	Glasses_Summary AS (
    	SELECT
        	O.Order_ID,
        	SUM(G.Units) AS Units_Glasses,
        	SUM(G.Units * VP.Total_Price) AS Cost_Glasses
    	FROM Customer_Orders O
    	INNER JOIN GLASSES_ORDERED G
        	ON O.Order_ID = G.Order_ID
    	INNER JOIN Version_Prices VP
        	ON G.Product_ID = VP.Product_ID AND G.Version = VP.Version
    	GROUP BY O.Order_ID
	)
	SELECT
    	CO.Order_ID,
    	CO.[Date],
    	ISNULL(OS.Units_Ordered, 0) + ISNULL(GS.Units_Glasses, 0) AS Total_Units,
    	ISNULL(OS.Cost_Ordered, 0) + ISNULL(GS.Cost_Glasses, 0) AS Total_Cost
	FROM Customer_Orders CO
	LEFT JOIN Ordered_Summary OS
    	ON CO.Order_ID = OS.Order_ID
	LEFT JOIN Glasses_Summary GS
    	ON CO.Order_ID = GS.Order_ID
)

GO

--פרק שני בונוס

--נושא ראשון PIVOT
SELECT
	P.Product_ID,
	P.Name,
	ISNULL(Sales.[2023], 0) AS Units_2023,
	ISNULL(Sales.[2024], 0) AS Units_2024,
	ISNULL(Sales.[2025], 0) AS Units_2025
FROM PRODUCTS P
JOIN (
	SELECT *
	FROM (
    	SELECT
        	G.Product_ID,
        	YEAR(O.Date) AS Sale_Year,
        	G.Units
    	FROM GLASSES_ORDERED G
    	JOIN ORDERS O ON G.Order_ID = O.Order_ID
	) AS SourceTable
	PIVOT (
    	SUM(Units)
    	FOR Sale_Year IN ([2023], [2024], [2025])
	) AS PivotTable
) AS Sales ON P.Product_ID = Sales.Product_ID

GO

--נושא שני TRY CATCH

--יצירת טבלת LOG
CREATE TABLE EmailErrorLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    EmailAddress NVARCHAR(255),
    ErrorDescription NVARCHAR(500),
    LogDate DATETIME DEFAULT GETDATE()
)

GO

--יצירת הפרוצדורה 
CREATE PROCEDURE AddCustomerWithEmailValidation
		@FirstName NVARCHAR(100),
    	@LastName NVARCHAR(100),
    	@Email NVARCHAR(255)
AS
BEGIN
	BEGIN TRY
        -- @ בדיקת
        IF CHARINDEX('@', @Email) = 0
        BEGIN
            THROW 51001, 'Invalid email address: missing @ symbol.', 1;
        END
 
        -- בדיקת נקודה
        IF CHARINDEX('.', @Email) = 0
        BEGIN
            THROW 51002, 'Invalid email address: missing dot (.) symbol.', 1;
        END
 
        -- שליפת הסיומת 
        DECLARE @Suffix NVARCHAR(50);
        SET @Suffix = LOWER(RIGHT(@Email, CHARINDEX('.', REVERSE(@Email)) - 1));
 
        -- בדיקת סיומת חוקית
        IF @Suffix NOT IN ('com', 'net', 'org', 'co.il', 'gov', 'edu')
        BEGIN
            THROW 51003, 'Invalid email domain suffix. Allowed: com, net, org, 
						  co.il, gov, edu.', 1;
        END
 
        -- הוספת הלקוח אם כל הבדיקות עברו
		DECLARE @Customer_ID INT;
		SELECT @Customer_ID = ISNULL(MAX(Customer_ID), 0) + 1 FROM CUSTOMERS;
		INSERT INTO Customers (Customer_ID, First_Name, Last_Name, Email)
        VALUES (@Customer_ID, @FirstName, @LastName, @Email);
 
        PRINT 'Customer added successfully.';
	END TRY
	BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
 
        INSERT INTO EmailErrorLog (EmailAddress, ErrorDescription)
        VALUES (@Email, @ErrorMessage);
 
        PRINT 'Failed to add customer. Error logged.';
        PRINT 'Error Message: ' + @ErrorMessage;
	END CATCH
END;

