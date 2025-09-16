const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const { createClient } = require('@supabase/supabase-js');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const helmet = require('helmet');
const morgan = require('morgan');
const nodemailer = require('nodemailer');
const { jsPDF } = require('jspdf');
require('jspdf-autotable');

dotenv.config();

const app = express();
app.use(helmet());
app.use(morgan('combined'));
app.use(cors());
app.use(express.json());

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
const JWT_SECRET = process.env.JWT_SECRET;

const authenticateToken = (req, res, next) => {
  const token = req.headers['authorization']?.split(' ')[1];
  if (!token) return res.sendStatus(401);
  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) return res.sendStatus(403);
    req.user = user;
    next();
  });
};

const requireSystemAdmin = (req, res, next) => {
  if (req.user.role !== 'system_admin') {
    return res.status(403).json({ error: 'Access denied' });
  }
  next();
};

app.get('/', (req, res) => {
  res.json({ message: "ShiftMaster Backend is running!" });
});

app.get('/setup-admin', async (req, res) => {
  const { data: existing } = await supabase
    .from('users')
    .select('*')
    .eq('username', 'zvika');

  if (existing && existing.length > 0) {
    return res.json({ message: "Admin user already exists" });
  }

  const hashedPassword = await bcrypt.hash('Zz321321', 10);
  const { data, error } = await supabase
    .from('users')
    .insert([
      {
        username: 'zvika',
        password: hashedPassword,
        role: 'system_admin',
        company_id: null,
        full_name: 'זיויקה מנהל מערכת'
      }
    ])
    .select();

  if (error) return res.status(500).json({ error: error.message });
  res.json({ message: "Admin user 'zvika' created!", user: data });
});

app.post('/login', async (req, res) => {
  const { username, password } = req.body;
  const { data, error } = await supabase
    .from('users')
    .select('*')
    .eq('username', username)
    .single();

  if (error || !data) return res.status(401).json({ error: 'Invalid credentials' });

  const valid = await bcrypt.compare(password, data.password);
  if (!valid) return res.status(401).json({ error: 'Invalid credentials' });

  const payload = {
    id: data.id,
    username: data.username,
    role: data.role,
    company_id: data.company_id
  };

  const token = jwt.sign(payload, JWT_SECRET);
  res.json({ token, user: payload });
});

app.get('/company', authenticateToken, async (req, res) => {
  if (!req.user.company_id) {
    return res.json({ company: null });
  }

  const { data, error } = await supabase
    .from('companies')
    .select('*')
    .eq('id', req.user.company_id)
    .single();

  if (error) return res.status(500).json({ error: error.message });
  res.json({ company: data });
});

app.post('/companies', authenticateToken, requireSystemAdmin, async (req, res) => {
  const { name, color, logo_url } = req.body;
  const { data, error } = await supabase
    .from('companies')
    .insert([{ name, color: color || '#3B82F6', logo_url: logo_url || '' }])
    .select();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

app.get('/companies', authenticateToken, requireSystemAdmin, async (req, res) => {
  const { data, error } = await supabase
    .from('companies')
    .select('*');

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

app.put('/companies/:id', authenticateToken, requireSystemAdmin, async (req, res) => {
  const { name, color, logo_url } = req.body;
  const { data, error } = await supabase
    .from('companies')
    .update({ name, color, logo_url })
    .eq('id', req.params.id)
    .select();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

app.get('/shifts', authenticateToken, async (req, res) => {
  if (!req.user.company_id) {
    return res.status(400).json({ error: 'No company assigned' });
  }

  const { data, error } = await supabase
    .from('shifts')
    .select('*, users(full_name)')
    .eq('company_id', req.user.company_id);

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

app.post('/shifts', authenticateToken, async (req, res) => {
  if (!req.user.company_id) {
    return res.status(400).json({ error: 'No company assigned' });
  }

  const { date, worker_id, hours, notes, color } = req.body;
  const { data, error } = await supabase
    .from('shifts')
    .insert([
      {
        date,
        worker_id,
        hours,
        notes: notes || '',
        color: color || '#3B82F6',
        company_id: req.user.company_id
      }
    ])
    .select();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

app.get('/workers', authenticateToken, async (req, res) => {
  if (!req.user.company_id) {
    return res.status(400).json({ error: 'No company assigned' });
  }

  const { data, error } = await supabase
    .from('users')
    .select('id, username, full_name, role')
    .eq('company_id', req.user.company_id)
    .neq('role', 'system_admin');

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

app.get('/vacations', authenticateToken, async (req, res) => {
  if (!req.user.company_id) {
    return res.status(400).json({ error: 'No company assigned' });
  }

  const { data, error } = await supabase
    .from('vacations')
    .select('*, users(full_name)')
    .eq('company_id', req.user.company_id)
    .in('status', ['pending', 'approved']);

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

app.get('/export/pdf', authenticateToken, async (req, res) => {
  if (!req.user.company_id) {
    return res.status(400).json({ error: 'No company assigned' });
  }

  const { data: company } = await supabase
    .from('companies')
    .select('name, color')
    .eq('id', req.user.company_id)
    .single();

  const { data: shifts } = await supabase
    .from('shifts')
    .select('date, hours, notes, color, users(full_name)')
    .eq('company_id', req.user.company_id)
    .order('date', { ascending: true });

  const doc = new jsPDF();
  doc.setFontSize(20);
  doc.setTextColor(company.color || '#3B82F6');
  doc.text(company.name || 'Company', 14, 22);
  doc.setFontSize(12);
  doc.setTextColor(0);
  doc.text('דוח משמרות', 14, 30);

  const tableData = shifts.map(shift => [
    shift.date,
    shift.hours,
    shift.notes || '-',
    shift.users?.full_name || 'N/A',
    shift.color
  ]);

  (doc as any).autoTable({
    head: [['תאריך', 'שעות', 'הערות', 'עובד', 'צבע']],
    body: tableData,
    startY: 40,
    theme: 'striped',
    headStyles: { fillColor: [59, 130, 246] }
  });

  const pdfBuffer = doc.output('arraybuffer');
  res.setHeader('Content-Disposition', 'attachment; filename="shifts.pdf"');
  res.setHeader('Content-Type', 'application/pdf');
  res.send(Buffer.from(pdfBuffer));
});

app.post('/users', authenticateToken, requireSystemAdmin, async (req, res) => {
  const { username, password, full_name, role, company_id } = req.body;
  const hashedPassword = await bcrypt.hash(password, 10);

  const { data, error } = await supabase
    .from('users')
    .insert([
      {
        username,
        password: hashedPassword,
        full_name,
        role: role || 'worker',
        company_id
      }
    ])
    .select();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});
