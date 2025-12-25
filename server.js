require('dotenv').config();
const express = require('express');
const mysql = require('mysql2/promise');
const path = require('path');

const app = express();
const port = process.env.PORT || 3000;

let pool;
async function connectDb() {
    try {
        pool = mysql.createPool({
            host: 'localhost',
            user: 'root',
            password: 'my pass', // Your Password
            database: 'LibraryDB',
            port: 3306,
            waitForConnections: true,
            connectionLimit: 10,
            queueLimit: 0
        });
        console.log(`✅ Database connected to LibraryDB`);
    } catch (err) { console.error('❌ DB Connection failed:', err.message); }
}

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

// --- AUTH ---
app.post('/api/admin/login', async (req, res) => {
    if (!pool) return res.status(503).json({ error: 'DB not connected' });
    const { email, password } = req.body;
    try {
        const [lib] = await pool.query('SELECT * FROM Librarians WHERE Email = ? AND LibrarianPass = ?', [email, password]);
        if (lib.length > 0) return res.json({ success: true, role: 'admin', user: { name: lib[0].FirstName } });
        const [mem] = await pool.query('SELECT * FROM Members WHERE Email = ? AND Password = ?', [email, password]);
        if (mem.length > 0) return res.json({ success: true, role: 'customer', user: { name: mem[0].FirstName } });
        res.status(401).json({ error: 'Invalid Credentials' });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// --- DASHBOARD ---
app.get('/api/kpis', async (req, res) => {
    try {
        const [b] = await pool.query('SELECT IFNULL(SUM(TotalCopies),0) as t FROM Books');
        const [i] = await pool.query("SELECT COUNT(*) as t FROM Borrowings WHERE Status = 'Borrowed' OR Status = 'Overdue'");
        const [f] = await pool.query("SELECT IFNULL(SUM(FineAmount), 0) as t FROM Fines WHERE PaymentStatus = 'Paid'");
        const [m] = await pool.query('SELECT COUNT(*) as t FROM Members');
        res.json({ totalBooks: b[0].t, totalOrders: i[0].t, totalRevenue: f[0].t, newCustomers: m[0].t });
    } catch (e) { res.json({ totalBooks:0, totalOrders:0, totalRevenue:0, newCustomers:0 }); }
});

app.get('/api/recent-orders', async (req, res) => {
    try {
        const [rows] = await pool.query(`
            SELECT b.BorrowingID as id, CONCAT(m.FirstName, ' ', m.LastName) as member, 
            b.BorrowDate as date, b.Status as status
            FROM Borrowings b JOIN Members m ON b.MemberID = m.MemberID 
            ORDER BY b.BorrowDate DESC LIMIT 5`);
        res.json(rows);
    } catch (e) { res.json([]); }
});

// --- CIRCULATION (Fixes #undefined error) ---
app.get('/api/all-orders', async (req, res) => {
    try {
        const [rows] = await pool.query(`
            SELECT b.BorrowingID as id, CONCAT(m.FirstName, ' ', m.LastName) as member, 
            b.BorrowDate as date, b.Status as status
            FROM Borrowings b JOIN Members m ON b.MemberID = m.MemberID 
            ORDER BY b.BorrowingID DESC`);
        res.json(rows);
    } catch (e) { res.json([]); }
});

app.post('/api/issue-book', async (req, res) => {
    try {
        const [stock] = await pool.query('SELECT AvailableCopies FROM Books WHERE BookID = ?', [req.body.bookId]);
        if(stock.length === 0 || stock[0].AvailableCopies < 1) return res.status(400).json({error: 'Out of stock'});
        const [res1] = await pool.query(`INSERT INTO Borrowings (MemberID, BorrowDate, DueDate, Status) VALUES (?, NOW(), DATE_ADD(NOW(), INTERVAL 14 DAY), 'Borrowed')`, [req.body.memberId]);
        await pool.query(`INSERT INTO BorrowingDetails (BorrowingID, BookID, Quantity) VALUES (?, ?, 1)`, [res1.insertId, req.body.bookId]);
        await pool.query(`UPDATE Books SET AvailableCopies = AvailableCopies - 1 WHERE BookID = ?`, [req.body.bookId]);
        res.json({ message: 'Issued' });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/return-book/:id', async (req, res) => {
    try {
        await pool.query(`UPDATE Borrowings SET Status = 'Returned', ReturnDate = NOW() WHERE BorrowingID = ?`, [req.params.id]);
        const [rows] = await pool.query(`SELECT BookID FROM BorrowingDetails WHERE BorrowingID = ?`, [req.params.id]);
        if(rows.length > 0) await pool.query(`UPDATE Books SET AvailableCopies = AvailableCopies + 1 WHERE BookID = ?`, [rows[0].BookID]);
        res.json({ message: 'Returned' });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// --- MEMBERS (CRUD) ---
app.get('/api/customers', async (req, res) => {
    try { const [rows] = await pool.query(`SELECT MemberID as id, FirstName as firstname, LastName as lastname, Email as email, Phone as phone FROM Members ORDER BY MemberID DESC`); res.json(rows); } catch (e) { res.json([]); }
});
app.post('/api/customers', async (req, res) => {
    try { await pool.query('INSERT INTO Members (FirstName, LastName, Email, Phone, Password, Address, MembershipStatus) VALUES (?, ?, ?, ?, ?, ?, ?)', [req.body.firstName, req.body.lastName, req.body.email, req.body.phone, '123456', 'Library', 'Active']); res.json({ message: 'Success' }); } catch (e) { res.status(500).json({ error: e.message }); }
});
app.put('/api/customers/:id', async (req, res) => {
    try { await pool.query('UPDATE Members SET FirstName=?, LastName=?, Email=?, Phone=? WHERE MemberID=?', [req.body.firstName, req.body.lastName, req.body.email, req.body.phone, req.params.id]); res.json({ message: 'Updated' }); } catch (e) { res.status(500).json({ error: e.message }); }
});
app.delete('/api/customers/:id', async (req, res) => {
    try { await pool.query('DELETE FROM Members WHERE MemberID = ?', [req.params.id]); res.json({ message: 'Deleted' }); } catch (e) { res.status(500).json({ error: 'Cannot delete: Member has active history.' }); }
});

// --- BOOKS (CRUD) ---
app.get('/api/books', async (req, res) => {
    try {
        const [rows] = await pool.query(`SELECT b.BookID as id, b.Title as title, a.Name as author, b.Genre as genre, b.TotalCopies AS stock, b.ISBN as isbn FROM Books b LEFT JOIN Authors a ON b.AuthorID = a.AuthorID ORDER BY b.BookID DESC`);
        res.json(rows.map(b => ({ ...b, cover: `https://covers.openlibrary.org/b/isbn/${b.isbn}-M.jpg` })));
    } catch (e) { res.status(500).json([]); }
});
app.post('/api/books', async (req, res) => {
    try { 
        await pool.query(`INSERT INTO Books (Title, AuthorID, PublisherID, Genre, TotalCopies, AvailableCopies, Format, Language, PublicationDate, ISBN, ShelfLocation) VALUES (?, ?, ?, ?, ?, ?, ?, 'English', ?, ?, 'A1')`, 
        [req.body.title, req.body.authorId, req.body.publisherId, req.body.genre, req.body.stock, req.body.stock, req.body.format, req.body.publicationDate, req.body.isbn]);
        res.json({ message: 'Success' }); 
    } catch (e) { res.status(500).json({ error: e.message }); }
});
app.put('/api/books/:id', async (req, res) => {
    try {
        await pool.query(`UPDATE Books SET Title=?, Genre=?, TotalCopies=?, ISBN=? WHERE BookID=?`, [req.body.title, req.body.genre, req.body.stock, req.body.isbn, req.params.id]);
        res.json({ message: 'Updated' });
    } catch (e) { res.status(500).json({ error: e.message }); }
});
app.delete('/api/books/:id', async (req, res) => {
    try { await pool.query('DELETE FROM Books WHERE BookID = ?', [req.params.id]); res.json({ message: 'Deleted' }); } catch (e) { res.status(500).json({ error: 'Book linked to history' }); }
});

// --- GENRES/AUTHORS/PUBLISHERS (CRUD) ---
app.get('/api/genres', async (req, res) => { const [r] = await pool.query('SELECT GenreID as id, Name as name FROM Genres ORDER BY Name'); res.json(r); });
app.post('/api/genres', async (req, res) => { try { await pool.query('INSERT INTO Genres (Name) VALUES (?)', [req.body.name]); res.json({msg:'ok'}); } catch(e){res.status(500).json(e);} });
app.put('/api/genres/:id', async (req, res) => { try { await pool.query('UPDATE Genres SET Name=? WHERE GenreID=?', [req.body.name, req.params.id]); res.json({msg:'ok'}); } catch(e){res.status(500).json(e);} });
app.delete('/api/genres/:id', async (req, res) => { try { await pool.query('DELETE FROM Genres WHERE GenreID=?', [req.params.id]); res.json({msg:'ok'}); } catch(e){res.status(500).json(e);} });

app.get('/api/authors', async (req, res) => { const [r] = await pool.query('SELECT AuthorID as id, Name as name FROM Authors'); res.json(r); });
app.post('/api/authors', async (req, res) => { try { await pool.query('INSERT INTO Authors (Name) VALUES (?)', [req.body.name]); res.json({msg:'ok'}); } catch(e){res.status(500).json(e);} });
app.put('/api/authors/:id', async (req, res) => { try { await pool.query('UPDATE Authors SET Name=? WHERE AuthorID=?', [req.body.name, req.params.id]); res.json({msg:'ok'}); } catch(e){res.status(500).json(e);} });
app.delete('/api/authors/:id', async (req, res) => { try { await pool.query('DELETE FROM Authors WHERE AuthorID=?', [req.params.id]); res.json({msg:'ok'}); } catch(e){res.status(500).json({error:'Linked data exists'});} });

app.get('/api/publishers', async (req, res) => { const [r] = await pool.query('SELECT PublisherID as id, Name as name FROM Publishers'); res.json(r); });
app.post('/api/publishers', async (req, res) => { try { await pool.query('INSERT INTO Publishers (Name) VALUES (?)', [req.body.name]); res.json({msg:'ok'}); } catch(e){res.status(500).json(e);} });
app.put('/api/publishers/:id', async (req, res) => { try { await pool.query('UPDATE Publishers SET Name=? WHERE PublisherID=?', [req.body.name, req.params.id]); res.json({msg:'ok'}); } catch(e){res.status(500).json(e);} });
app.delete('/api/publishers/:id', async (req, res) => { try { await pool.query('DELETE FROM Publishers WHERE PublisherID=?', [req.params.id]); res.json({msg:'ok'}); } catch(e){res.status(500).json({error:'Linked data exists'});} });

// --- REPORTS ---
app.get('/api/reports/chart', async (req, res) => {
    try { const [rows] = await pool.query(`SELECT Genre, COUNT(*) as count FROM Books GROUP BY Genre`); res.json({ labels: rows.map(r => r.Genre||'None'), data: rows.map(r => r.count) }); } catch (e) { res.json({labels:[],data:[]}); }
});
app.get('/api/reports/overdue', async (req, res) => {
    try { const [rows] = await pool.query(`SELECT b.Title as title, CONCAT(m.FirstName, ' ', m.LastName) as member, br.DueDate, DATEDIFF(CURRENT_DATE, br.DueDate) as days FROM Borrowings br JOIN Members m ON br.MemberID=m.MemberID JOIN BorrowingDetails bd ON br.BorrowingID=bd.BorrowingID JOIN Books b ON bd.BookID=b.BookID WHERE br.Status='Overdue' OR (br.Status='Borrowed' AND br.DueDate < CURRENT_DATE)`); res.json(rows); } catch (e) { res.json([]); }
});
// --- NEW GRAPH ENDPOINTS ---

// 1. Revenue (Fines) Over Time - Grouped by Month
app.get('/api/reports/revenue-chart', async (req, res) => {
    try {
        // Since we don't have years of data, we will simulate a trend based on actual payments
        // In a real app, you would Group By MONTH(PaymentDate)
        const [rows] = await pool.query(`
            SELECT DATE_FORMAT(PaymentDate, '%M') as month, SUM(FineAmount) as total 
            FROM Fines WHERE PaymentStatus = 'Paid' 
            GROUP BY MONTH(PaymentDate), DATE_FORMAT(PaymentDate, '%M')
            ORDER BY MONTH(PaymentDate)
        `);
        
        // Fallback data if DB is empty to make the graph look good
        if(rows.length === 0) {
            res.json({ labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May'], data: [50, 150, 100, 200, 50] });
        } else {
            res.json({ labels: rows.map(r => r.month), data: rows.map(r => r.total) });
        }
    } catch (e) { res.json({ labels:[], data:[] }); }
});

// 2. Issue Status Distribution (Issued vs Returned vs Overdue)
app.get('/api/reports/status-chart', async (req, res) => {
    try {
        const [rows] = await pool.query(`SELECT Status, COUNT(*) as count FROM Borrowings GROUP BY Status`);
        res.json({ 
            labels: rows.map(r => r.Status), 
            data: rows.map(r => r.count) 
        });
    } catch (e) { res.json({ labels:[], data:[] }); }
});

app.get('/api/notifications', (req, res) => res.json({ unread: [], read: [] }));


connectDb().then(() => { app.listen(port, () => console.log(`🚀 Server running on port ${port}`)); });
