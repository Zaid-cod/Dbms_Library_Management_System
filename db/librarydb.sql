-- =====================================================
-- BOOKSTORE DATABASE - MySQL Version
-- Converted from SQL Server to MySQL
-- =====================================================
-- =====================================================
-- LIBRARY MANAGEMENT SYSTEM - MySQL Database Schema
-- =====================================================

DROP DATABASE IF EXISTS LibraryDB;
CREATE DATABASE LibraryDB;
USE LibraryDB;

-- =====================================================
-- TABLES
-- =====================================================

-- Authors Table (unchanged structure)
CREATE TABLE Authors (
    AuthorID INT AUTO_INCREMENT PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    DOB DATE,
    INDEX idx_author_name (Name)
);

-- Publishers Table (unchanged structure)
CREATE TABLE Publishers (
    PublisherID INT AUTO_INCREMENT PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Address VARCHAR(255),
    Contact VARCHAR(100),
    INDEX idx_publisher_name (Name)
);

-- Books Table (modified for library context)
CREATE TABLE Books (
    BookID INT AUTO_INCREMENT PRIMARY KEY,
    Title VARCHAR(200) NOT NULL,
    AuthorID INT NOT NULL,
    PublisherID INT NOT NULL,
    Genre VARCHAR(100),
    TotalCopies INT NOT NULL DEFAULT 1 CHECK (TotalCopies >= 0),
    AvailableCopies INT NOT NULL DEFAULT 1 CHECK (AvailableCopies >= 0),
    Format VARCHAR(50) CHECK (Format IN ('eBook', 'Hardcover', 'Paperback')),
    Language VARCHAR(50),
    PublicationDate DATE,
    ISBN VARCHAR(17),
    ShelfLocation VARCHAR(50),
    FOREIGN KEY (AuthorID) REFERENCES Authors(AuthorID),
    FOREIGN KEY (PublisherID) REFERENCES Publishers(PublisherID),
    INDEX idx_books_title (Title),
    INDEX idx_books_isbn (ISBN),
    INDEX idx_books_genre (Genre)
);

-- Members Table (replaces Customers)
CREATE TABLE Members (
    MemberID INT AUTO_INCREMENT PRIMARY KEY,
    FirstName VARCHAR(100) NOT NULL,
    LastName VARCHAR(100) NOT NULL,
    Email VARCHAR(100) NOT NULL UNIQUE,
    Phone VARCHAR(20),
    Password VARCHAR(255),
    Address VARCHAR(255),
    MembershipDate DATE DEFAULT (CURRENT_DATE),
    MembershipStatus VARCHAR(20) DEFAULT 'Active' CHECK (MembershipStatus IN ('Active', 'Suspended', 'Expired')),
    INDEX idx_member_email (Email),
    INDEX idx_member_name (LastName, FirstName)
);

-- Borrowings Table (replaces Orders)
CREATE TABLE Borrowings (
    BorrowingID INT AUTO_INCREMENT PRIMARY KEY,
    MemberID INT NOT NULL,
    BorrowDate DATE DEFAULT (CURRENT_DATE),
    DueDate DATE NOT NULL,
    ReturnDate DATE NULL,
    Status VARCHAR(50) DEFAULT 'Borrowed' CHECK (Status IN ('Borrowed', 'Returned', 'Overdue', 'Lost')),
    FOREIGN KEY (MemberID) REFERENCES Members(MemberID),
    INDEX idx_borrowing_status (Status),
    INDEX idx_borrowing_dates (BorrowDate, DueDate)
);

-- BorrowingDetails Table (replaces OrderDetails)
CREATE TABLE BorrowingDetails (
    BorrowingDetailID INT AUTO_INCREMENT PRIMARY KEY,
    BorrowingID INT NOT NULL,
    BookID INT NOT NULL,
    Quantity INT DEFAULT 1 CHECK (Quantity > 0),
    FOREIGN KEY (BorrowingID) REFERENCES Borrowings(BorrowingID),
    FOREIGN KEY (BookID) REFERENCES Books(BookID),
    INDEX idx_borrowing_book (BorrowingID, BookID)
);

-- Fines Table (replaces Payments)
CREATE TABLE Fines (
    FineID INT AUTO_INCREMENT PRIMARY KEY,
    BorrowingID INT NOT NULL,
    FineAmount DECIMAL(10, 2) DEFAULT 0.00 CHECK (FineAmount >= 0),
    FineReason VARCHAR(100),
    PaymentStatus VARCHAR(50) DEFAULT 'Unpaid' CHECK (PaymentStatus IN ('Paid', 'Unpaid', 'Waived')),
    PaymentDate DATETIME NULL,
    PaymentMethod VARCHAR(50) CHECK (PaymentMethod IN ('Cash', 'Card', 'Online', NULL)),
    FOREIGN KEY (BorrowingID) REFERENCES Borrowings(BorrowingID),
    INDEX idx_fine_status (PaymentStatus)
);

-- Librarians Table (replaces Admins)
CREATE TABLE Librarians (
    LibrarianID INT AUTO_INCREMENT PRIMARY KEY,
    Email VARCHAR(100) NOT NULL UNIQUE,
    LibrarianPass VARCHAR(255) NOT NULL,
    FirstName VARCHAR(50),
    LastName VARCHAR(50),
    IsActive BOOLEAN DEFAULT TRUE,
    CreatedDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    LastLoginDate DATETIME,
    UpdatedDate DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_librarian_email (Email)
);

-- ActivityLog Table (replaces OrderLog)
CREATE TABLE ActivityLog (
    LogID INT AUTO_INCREMENT PRIMARY KEY,
    BorrowingID INT,
    ActivityType VARCHAR(50),
    LogDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    Notes TEXT,
    FOREIGN KEY (BorrowingID) REFERENCES Borrowings(BorrowingID),
    INDEX idx_log_date (LogDate)
);

-- =====================================================
-- VIEWS
-- =====================================================

-- 1. BookDetails: Full book info with author and publisher
CREATE VIEW BookDetails AS
SELECT 
    b.BookID, b.Title, a.Name AS AuthorName, p.Name AS PublisherName,
    b.Genre, b.TotalCopies, b.AvailableCopies, b.Format, b.Language, 
    b.PublicationDate, b.ISBN, b.ShelfLocation
FROM Books b
JOIN Authors a ON b.AuthorID = a.AuthorID
JOIN Publishers p ON b.PublisherID = p.PublisherID;

-- 2. BorrowingSummary: Borrowings with member info
CREATE VIEW BorrowingSummary AS
SELECT 
    br.BorrowingID, 
    CONCAT(m.FirstName, ' ', m.LastName) AS MemberName,
    m.MemberID,
    br.BorrowDate,
    br.DueDate,
    br.ReturnDate,
    br.Status,
    COUNT(bd.BorrowingDetailID) AS TotalItems,
    DATEDIFF(CURRENT_DATE, br.DueDate) AS DaysOverdue
FROM Borrowings br
JOIN Members m ON br.MemberID = m.MemberID
LEFT JOIN BorrowingDetails bd ON br.BorrowingID = bd.BorrowingID
GROUP BY br.BorrowingID, m.FirstName, m.LastName, m.MemberID, 
         br.BorrowDate, br.DueDate, br.ReturnDate, br.Status;

-- 3. MostBorrowedBooks: Top books by borrowing frequency
CREATE VIEW MostBorrowedBooks AS
SELECT 
    b.BookID,
    b.Title, 
    a.Name AS AuthorName,
    SUM(bd.Quantity) AS TotalBorrowed,
    b.AvailableCopies
FROM BorrowingDetails bd
JOIN Books b ON bd.BookID = b.BookID
JOIN Authors a ON b.AuthorID = a.AuthorID
GROUP BY b.BookID, b.Title, a.Name, b.AvailableCopies
ORDER BY TotalBorrowed DESC
LIMIT 10;

-- 4. MemberBorrowingHistory: Member borrowing records
CREATE VIEW MemberBorrowingHistory AS
SELECT
    m.MemberID,
    m.FirstName,
    m.LastName,
    m.Email,
    br.BorrowingID,
    br.BorrowDate,
    br.DueDate,
    br.ReturnDate,
    br.Status,
    f.FineAmount,
    f.PaymentStatus
FROM Members m
LEFT JOIN Borrowings br ON m.MemberID = br.MemberID
LEFT JOIN Fines f ON br.BorrowingID = f.BorrowingID;

-- 5. AvailableBooks: Books with available copies
CREATE VIEW AvailableBooks AS
SELECT 
    BookID, 
    Title, 
    AvailableCopies,
    TotalCopies,
    ShelfLocation
FROM Books
WHERE AvailableCopies > 0;

-- =====================================================
-- STORED PROCEDURES
-- =====================================================

-- 1. AddBook Procedure
DELIMITER //
CREATE PROCEDURE AddBook(
    IN p_Title VARCHAR(200),
    IN p_AuthorID INT,
    IN p_PublisherID INT,
    IN p_Genre VARCHAR(100),
    IN p_TotalCopies INT,
    IN p_Format VARCHAR(50),
    IN p_Language VARCHAR(50),
    IN p_PublicationDate DATE,
    IN p_ISBN VARCHAR(17),
    IN p_ShelfLocation VARCHAR(50)
)
BEGIN
    INSERT INTO Books (
        Title, AuthorID, PublisherID, Genre, TotalCopies, 
        AvailableCopies, Format, Language, PublicationDate, ISBN, ShelfLocation
    )
    VALUES (
        p_Title, p_AuthorID, p_PublisherID, p_Genre, p_TotalCopies,
        p_TotalCopies, p_Format, p_Language, p_PublicationDate, p_ISBN, p_ShelfLocation
    );
END //
DELIMITER ;

-- 2. RegisterMember Procedure
DELIMITER //
CREATE PROCEDURE RegisterMember(
    IN p_FirstName VARCHAR(100),
    IN p_LastName VARCHAR(100),
    IN p_Email VARCHAR(100),
    IN p_Phone VARCHAR(20),
    IN p_Password VARCHAR(255),
    IN p_Address VARCHAR(255)
)
BEGIN
    INSERT INTO Members (FirstName, LastName, Email, Phone, Password, Address)
    VALUES (p_FirstName, p_LastName, p_Email, p_Phone, p_Password, p_Address);
END //
DELIMITER ;

-- 3. UpdateBookAvailability Procedure
DELIMITER //
CREATE PROCEDURE UpdateBookAvailability(
    IN p_BookID INT,
    IN p_CopyChange INT
)
BEGIN
    UPDATE Books
    SET AvailableCopies = AvailableCopies + p_CopyChange
    WHERE BookID = p_BookID 
      AND AvailableCopies + p_CopyChange >= 0
      AND AvailableCopies + p_CopyChange <= TotalCopies;
END //
DELIMITER ;

-- 4. BorrowBook Procedure (Simplified - single book)
DELIMITER //
CREATE PROCEDURE BorrowBook(
    IN p_MemberID INT,
    IN p_BookID INT,
    IN p_Quantity INT,
    IN p_LoanDays INT
)
BEGIN
    DECLARE v_BorrowingID INT;
    DECLARE v_DueDate DATE;
    
    START TRANSACTION;
    
    -- Calculate due date
    SET v_DueDate = DATE_ADD(CURRENT_DATE, INTERVAL p_LoanDays DAY);
    
    -- Create borrowing record
    INSERT INTO Borrowings (MemberID, DueDate)
    VALUES (p_MemberID, v_DueDate);
    
    SET v_BorrowingID = LAST_INSERT_ID();
    
    -- Add borrowing details
    INSERT INTO BorrowingDetails (BorrowingID, BookID, Quantity)
    VALUES (v_BorrowingID, p_BookID, p_Quantity);
    
    -- Update book availability
    UPDATE Books
    SET AvailableCopies = AvailableCopies - p_Quantity
    WHERE BookID = p_BookID AND AvailableCopies >= p_Quantity;
    
    -- Log activity
    INSERT INTO ActivityLog (BorrowingID, ActivityType, Notes)
    VALUES (v_BorrowingID, 'Book Borrowed', CONCAT('Book ID: ', p_BookID, ', Quantity: ', p_Quantity));
    
    COMMIT;
    
    SELECT v_BorrowingID AS BorrowingID, v_DueDate AS DueDate;
END //
DELIMITER ;

-- =====================================================
-- SAMPLE DATA
-- =====================================================

-- Insert sample authors
INSERT INTO Authors (Name, DOB) VALUES 
('J.K. Rowling', '1965-07-31'),
('George Orwell', '1903-06-25'),
('Harper Lee', '1926-04-28'),
('Paulo Coelho', '1947-08-24'),
('Khaled Hosseini', '1965-03-04');

-- Insert sample publishers
INSERT INTO Publishers (Name, Address, Contact) VALUES 
('Bloomsbury Publishing', 'London, UK', 'contact@bloomsbury.com'),
('Penguin Books', 'London, UK', 'info@penguin.co.uk'),
('HarperCollins', 'New York, USA', 'help@harpercollins.com');

-- Insert sample books
INSERT INTO Books (Title, AuthorID, PublisherID, Genre, TotalCopies, AvailableCopies, Format, Language, PublicationDate, ISBN, ShelfLocation) VALUES 
('Harry Potter and the Philosopher''s Stone', 1, 1, 'Fantasy', 5, 3, 'Hardcover', 'English', '1997-06-26', '978-0-7475-3269-9', 'A1-F3'),
('1984', 2, 2, 'Dystopian Fiction', 4, 4, 'Paperback', 'English', '1949-06-08', '978-0451524935', 'B2-D1'),
('To Kill a Mockingbird', 3, 3, 'Classic Fiction', 3, 2, 'Hardcover', 'English', '1960-07-11', '978-0061120084', 'C1-A2'),
('The Alchemist', 4, 3, 'Fiction', 6, 5, 'Paperback', 'English', '1988-01-01', '978-0062315007', 'D3-B4');

-- Insert sample members
INSERT INTO Members (FirstName, LastName, Email, Phone, Password, Address, MembershipStatus) VALUES 
('Ahmed', 'Khan', 'ahmed.khan@email.com', '03001234567', 'pass123', 'House 12, Block A, Gulshan', 'Active'),
('Fatima', 'Ali', 'fatima.ali@email.com', '03219876543', 'pass456', 'Flat 4B, Clifton', 'Active'),
('Hassan', 'Sheikh', 'hassan.s@email.com', '03335555555', 'pass789', 'Sector F-7, Islamabad', 'Active');

-- Insert sample borrowings
INSERT INTO Borrowings (MemberID, BorrowDate, DueDate, Status) VALUES 
(1, '2024-12-01', '2024-12-15', 'Returned'),
(2, '2024-12-10', '2024-12-24', 'Borrowed'),
(3, '2024-12-15', '2024-12-29', 'Borrowed');

-- Insert borrowing details
INSERT INTO BorrowingDetails (BorrowingID, BookID, Quantity) VALUES 
(1, 1, 1),
(2, 2, 1),
(3, 4, 1);

-- Insert sample fines
INSERT INTO Fines (BorrowingID, FineAmount, FineReason, PaymentStatus) VALUES 
(1, 50.00, 'Late return - 5 days', 'Paid');

-- Insert sample librarians
INSERT INTO Librarians (Email, LibrarianPass, FirstName, LastName) VALUES 
('librarian@library.com', 'lib_pass123', 'System', 'Librarian'),
('admin@library.com', 'admin_pass123', 'Head', 'Librarian');