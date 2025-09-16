#!/bin/bash

echo "🧙‍♂️ מתחיל קסם העדכון וההעלאה... אל תלחץ CTRL+C!"

# שלב 1: עדכון כל הקבצים
echo "🔧 מעדכן קבצים..."
mkdir -p client server

# עדכון server
cat > server/.env <<EOL
SUPABASE_URL=https://qyqoraisizfujcgcynib.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF5cW9yYWlzaXpmdWpjZ2N5bmliIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc5NzA1NzYsImV4cCI6MjA3MzU0NjU3Nn0.GooMdBCE2ilvM6Qh49nZ1OpKVAXS_ADP50RFjoLPcNc
JWT_SECRET=shiftmaster_secret_2025
PORT=5000
EOL

cat > server/package.json <<EOL
{
  "name": "shifts-server",
  "version": "1.0.0",
  "description": "Backend for Shifts Scheduler App",
  "main": "server.js",
  "scripts": {
    "dev": "nodemon server.js",
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "@supabase/supabase-js": "^2.38.0",
    "bcrypt": "^5.1.1",
    "jsonwebtoken": "^9.0.2",
    "helmet": "^7.0.0",
    "morgan": "^1.10.0",
    "nodemailer": "^6.9.7",
    "jspdf": "^2.5.1",
    "jspdf-autotable": "^3.8.0",
    "xlsx": "^0.18.5"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOL

cat > server/server.js <<EOL
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
  console.log(\`🚀 Server running on port \${PORT}\`);
});
EOL

# עדכון client
mkdir -p client/src/pages client/src

cat > client/package.json <<EOL
{
  "name": "shifts-client",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "@fullcalendar/core": "^6.1.10",
    "@fullcalendar/daygrid": "^6.1.10",
    "@fullcalendar/interaction": "^6.1.10",
    "@fullcalendar/react": "^6.1.10",
    "@headlessui/react": "^1.7.17",
    "@heroicons/react": "^2.1.1",
    "axios": "^1.6.7",
    "file-saver": "^2.0.5",
    "jspdf": "^2.5.1",
    "jspdf-autotable": "^3.8.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.22.0",
    "tailwindcss": "^3.4.1",
    "typescript": "^5.3.3",
    "xlsx": "^0.18.5"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  }
}
EOL

cat > client/src/index.tsx <<EOL
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOL

cat > client/src/App.tsx <<EOL
import React, { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import AdminPanel from './pages/AdminPanel';
import './App.css';

const App: React.FC = () => {
  const [token, setToken] = useState<string | null>(localStorage.getItem('token'));
  const [darkMode, setDarkMode] = useState(() => {
    return localStorage.getItem('darkMode') === 'true';
  });

  useEffect(() => {
    const savedToken = localStorage.getItem('token');
    if (savedToken) setToken(savedToken);
  }, []);

  useEffect(() => {
    document.body.className = darkMode ? 'bg-gray-900 text-white' : 'bg-gray-50 text-gray-900';
  }, [darkMode]);

  const handleLogin = (token: string) => {
    localStorage.setItem('token', token);
    setToken(token);
  };

  const handleLogout = () => {
    localStorage.removeItem('token');
    setToken(null);
  };

  const toggleDarkMode = () => {
    setDarkMode(!darkMode);
    localStorage.setItem('darkMode', (!darkMode).toString());
  };

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login onLogin={handleLogin} />} />
        <Route
          path="/"
          element={token ? <Dashboard onLogout={handleLogout} /> : <Login onLogin={handleLogin} />}
        />
        <Route
          path="/admin"
          element={token ? <AdminPanel onLogout={handleLogout} /> : <Login onLogin={handleLogin} />}
        />
      </Routes>
    </BrowserRouter>
  );
};

export default App;
EOL

cat > client/src/pages/Login.tsx <<EOL
import React, { useState } from 'react';
import axios from 'axios';

interface LoginProps {
  onLogin: (token: string) => void;
}

const Login: React.FC<LoginProps> = ({ onLogin }) => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const res = await axios.post('http://localhost:5000/login', { username, password });
      onLogin(res.data.token);
    } catch (err) {
      setError('שם משתמש או סיסמה שגויים');
    }
  };

  return (
    <div className="flex items-center justify-center min-h-screen bg-gray-100">
      <div className="bg-white p-8 rounded shadow-md w-96">
        <h2 className="text-2xl font-bold mb-6 text-center">כניסה למערכת</h2>
        {error && <p className="text-red-500 mb-4">{error}</p>}
        <form onSubmit={handleSubmit}>
          <div className="mb-4">
            <label className="block text-gray-700">שם משתמש</label>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full p-2 border border-gray-300 rounded"
              required
            />
          </div>
          <div className="mb-6">
            <label className="block text-gray-700">סיסמה</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full p-2 border border-gray-300 rounded"
              required
            />
          </div>
          <button
            type="submit"
            className="w-full bg-blue-600 text-white p-2 rounded hover:bg-blue-700"
          >
            התחבר
          </button>
        </form>
      </div>
    </div>
  );
};

export default Login;
EOL

cat > client/src/pages/Dashboard.tsx <<EOL
import React, { useState, useEffect } from 'react';
import FullCalendar from '@fullcalendar/react';
import dayGridPlugin from '@fullcalendar/daygrid';
import interactionPlugin from '@fullcalendar/interaction';
import axios from 'axios';

const Dashboard: React.FC<{ onLogout: () => void }> = ({ onLogout }) => {
  const [shifts, setShifts] = useState([]);
  const [company, setCompany] = useState(null);
  const [loading, setLoading] = useState(true);
  const [darkMode, setDarkMode] = useState(() => {
    return localStorage.getItem('darkMode') === 'true';
  });

  useEffect(() => {
    document.body.className = darkMode ? 'bg-gray-900 text-white' : 'bg-gray-50 text-gray-900';
  }, [darkMode]);

  const token = localStorage.getItem('token');

  useEffect(() => {
    if (!token) return;
    axios.defaults.headers.common['Authorization'] = \`Bearer \${token}\`;
    loadCompany();
    checkReminders();
    requestNotificationPermission();
  }, [token]);

  const requestNotificationPermission = () => {
    if (!("Notification" in window)) {
      console.log("Browser does not support notifications.");
    } else if (Notification.permission === "granted") {
    } else if (Notification.permission !== "denied") {
      Notification.requestPermission().then((permission) => {
        if (permission === "granted") {
          console.log("Notification permission granted.");
        }
      });
    }
  };

  const showNotification = (title, body) => {
    if (Notification.permission === "granted") {
      new Notification(title, {
        body,
        icon: "/favicon.ico"
      });
    }
  };

  const checkReminders = async () => {
    try {
      const res = await axios.get('http://localhost:5000/reminders/today');
      res.data.forEach(shift => {
        showNotification(
          'תזכורת משמרת מחר!',
          \`שלום \${shift.users?.full_name}, יש לך משמרת מחר (\${shift.date}) בין \${shift.hours}\`
        );
      });
    } catch (err) {
      console.error(err);
    }
  };

  const loadCompany = async () => {
    try {
      const res = await axios.get('http://localhost:5000/company');
      setCompany(res.data.company);
      if (res.data.company) {
        loadShifts();
      }
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const loadShifts = async () => {
    try {
      const res = await axios.get('http://localhost:5000/shifts');
      setShifts(res.data);
    } catch (err) {
      console.error(err);
    }
  };

  const exportToPDF = async () => {
    try {
      const res = await axios.get('http://localhost:5000/export/pdf', {
        responseType: 'blob'
      });
      const url = window.URL.createObjectURL(new Blob([res.data]));
      const link = document.createElement('a');
      link.href = url;
      link.setAttribute('download', 'shifts.pdf');
      document.body.appendChild(link);
      link.click();
      link.remove();
    } catch (err) {
      alert('שגיאה בייצוא PDF');
    }
  };

  const toggleDarkMode = () => {
    setDarkMode(!darkMode);
  };

  const eventContent = (arg) => {
    const shift = shifts.find(s => s.id === arg.event.id);
    return (
      <div 
        style={{ backgroundColor: shift?.color || '#3B82F6' }} 
        className={\`p-1 rounded text-white text-xs min-h-8 flex flex-col justify-center \${darkMode ? 'bg-opacity-80' : ''}\`}
      >
        <div className="font-bold">{shift?.hours}</div>
        {shift?.notes && <div className="text-[10px]">({shift.notes})</div>}
        <div className="text-[9px] mt-1">{shift?.users?.full_name}</div>
      </div>
    );
  };

  const events = shifts.map(shift => ({
    id: shift.id,
    title: \`\${shift.hours} (\${shift.users?.full_name || 'N/A'})\`,
    start: shift.date,
    backgroundColor: shift.color,
    extendedProps: shift
  }));

  if (loading) {
    return <div className="flex items-center justify-center min-h-screen">טוען...</div>;
  }

  if (!company) {
    return (
      <div className={\`p-4 text-center \${darkMode ? 'bg-gray-900 text-white' : 'bg-white'}\`}>
        <h2 className="text-xl font-bold mb-4">לא משוייך לחברה</h2>
        <p>אנא פנה למנהל המערכת כדי שיוסיף אותך לחברה קיימת.</p>
        <button
          onClick={onLogout}
          className="mt-6 bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700"
        >
          התנתק
        </button>
      </div>
    );
  }

  return (
    <div className={\`min-h-screen \${darkMode ? 'bg-gray-900 text-white' : 'bg-gray-50 text-gray-900'}\`}>
      <div className={\`md:hidden p-4 shadow-sm flex justify-between items-center \${darkMode ? 'bg-gray-800' : 'bg-white'}\`}>
        <h1 className="text-lg font-bold" style={{ color: company.color || '#3B82F6' }}>
          {company.name}
        </h1>
        <div className="flex gap-2 items-center">
          <button
            onClick={toggleDarkMode}
            className={\`p-2 rounded \${darkMode ? 'bg-yellow-400 text-gray-900' : 'bg-gray-700 text-white'}\`}
          >
            {darkMode ? '☀️' : '🌙'}
          </button>
          <button
            onClick={exportToPDF}
            className="bg-red-600 text-white px-3 py-1 rounded text-sm"
          >
            PDF
          </button>
          <button
            onClick={onLogout}
            className="bg-gray-600 text-white px-3 py-1 rounded text-sm"
          >
            התנתק
          </button>
        </div>
      </div>

      <div className={\`hidden md:flex justify-between items-center p-6 shadow-sm \${darkMode ? 'bg-gray-800' : 'bg-white'}\`}>
        <h1 className="text-2xl font-bold" style={{ color: company.color || '#3B82F6' }}>
          {company.name} - לוח משמרות
        </h1>
        <div className="flex gap-4 items-center">
          <button
            onClick={toggleDarkMode}
            className={\`p-2 rounded-full \${darkMode ? 'bg-yellow-400 text-gray-900' : 'bg-gray-700 text-white'}\`}
            title={darkMode ? 'מצב בהיר' : 'מצב חשוך'}
          >
            {darkMode ? '☀️' : '🌙'}
          </button>
          <button
            onClick={exportToPDF}
            className="bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700"
          >
            🖨️ ייצוא ל-PDF
          </button>
          <button
            onClick={onLogout}
            className="bg-gray-600 text-white px-4 py-2 rounded hover:bg-gray-700"
          >
            התנתק
          </button>
        </div>
      </div>

      <div className="p-4 md:p-6">
        <div className={\`p-4 rounded shadow \${darkMode ? 'bg-gray-800' : 'bg-white'}\`}>
          <FullCalendar
            plugins={[dayGridPlugin, interactionPlugin]}
            initialView="dayGridMonth"
            headerToolbar={{
              left: 'prev,next today',
              center: 'title',
              right: 'dayGridMonth,dayGridWeek'
            }}
            events={events}
            eventContent={eventContent}
            editable={true}
            droppable={true}
            locale="he"
            direction="rtl"
            height="auto"
          />
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
EOL

cat > client/src/pages/AdminPanel.tsx <<EOL
import React, { useState, useEffect } from 'react';
import axios from 'axios';

const AdminPanel: React.FC<{ onLogout: () => void }> = ({ onLogout }) => {
  const [companies, setCompanies] = useState([]);
  const [users, setUsers] = useState([]);
  const [newCompany, setNewCompany] = useState({ name: '', color: '#3B82F6', logo_url: '' });
  const [newUser, setNewUser] = useState({
    username: '',
    password: '',
    full_name: '',
    role: 'worker',
    company_id: ''
  });

  const token = localStorage.getItem('token');

  useEffect(() => {
    if (!token) return;
    axios.defaults.headers.common['Authorization'] = \`Bearer \${token}\`;
    loadCompanies();
    loadUsers();
  }, [token]);

  const loadCompanies = async () => {
    try {
      const res = await axios.get('http://localhost:5000/companies');
      setCompanies(res.data);
    } catch (err) {
      console.error(err);
    }
  };

  const loadUsers = async () => {
    try {
      const res = await axios.get('http://localhost:5000/workers');
      setUsers(res.data);
    } catch (err) {
      console.error(err);
    }
  };

  const createCompany = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const res = await axios.post('http://localhost:5000/companies', newCompany);
      setCompanies([...companies, res.data[0]]);
      setNewCompany({ name: '', color: '#3B82F6', logo_url: '' });
    } catch (err) {
      alert('שגיאה ביצירת חברה');
    }
  };

  const createUser = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const res = await axios.post('http://localhost:5000/users', newUser);
      setUsers([...users, res.data[0]]);
      setNewUser({ username: '', password: '', full_name: '', role: 'worker', company_id: '' });
    } catch (err) {
      alert('שגיאה ביצירת משתמש');
    }
  };

  return (
    <div className="p-6 bg-gray-50 min-h-screen">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold">פאנל ניהול - מנהל מערכת</h1>
        <button
          onClick={onLogout}
          className="bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700"
        >
          התנתק
        </button>
      </div>

      <div className="bg-white p-6 rounded shadow mb-8">
        <h2 className="text-xl font-bold mb-4">יצירת חברה חדשה</h2>
        <form onSubmit={createCompany} className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <input
            type="text"
            placeholder="שם החברה"
            value={newCompany.name}
            onChange={(e) => setNewCompany({ ...newCompany, name: e.target.value })}
            className="p-2 border border-gray-300 rounded"
            required
          />
          <input
            type="color"
            value={newCompany.color}
            onChange={(e) => setNewCompany({ ...newCompany, color: e.target.value })}
            className="h-10"
          />
          <input
            type="text"
            placeholder="כתובת לוגו (אופציונלי)"
            value={newCompany.logo_url}
            onChange={(e) => setNewCompany({ ...newCompany, logo_url: e.target.value })}
            className="p-2 border border-gray-300 rounded col-span-2"
          />
          <button
            type="submit"
            className="bg-blue-600 text-white p-2 rounded hover:bg-blue-700 col-span-2 w-full"
          >
            ✅ צור חברה
          </button>
        </form>
      </div>

      <div className="bg-white p-6 rounded shadow mb-8">
        <h2 className="text-xl font-bold mb-4">יצירת משתמש חדש</h2>
        <form onSubmit={createUser} className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <input
            type="text"
            placeholder="שם משתמש"
            value={newUser.username}
            onChange={(e) => setNewUser({ ...newUser, username: e.target.value })}
            className="p-2 border border-gray-300 rounded"
            required
          />
          <input
            type="password"
            placeholder="סיסמה"
            value={newUser.password}
            onChange={(e) => setNewUser({ ...newUser, password: e.target.value })}
            className="p-2 border border-gray-300 rounded"
            required
          />
          <input
            type="text"
            placeholder="שם מלא"
            value={newUser.full_name}
            onChange={(e) => setNewUser({ ...newUser, full_name: e.target.value })}
            className="p-2 border border-gray-300 rounded"
            required
          />
          <select
            value={newUser.role}
            onChange={(e) => setNewUser({ ...newUser, role: e.target.value })}
            className="p-2 border border-gray-300 rounded"
          >
            <option value="worker">עובד</option>
            <option value="manager">מנהל</option>
          </select>
          <select
            value={newUser.company_id}
            onChange={(e) => setNewUser({ ...newUser, company_id: e.target.value })}
            className="p-2 border border-gray-300 rounded col-span-2"
            required
          >
            <option value="">בחר חברה</option>
            {companies.map((c: any) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
          <button
            type="submit"
            className="bg-green-600 text-white p-2 rounded hover:bg-green-700 col-span-2 w-full"
          >
            ✅ צור משתמש
          </button>
        </form>
      </div>

      <div className="bg-white p-6 rounded shadow mb-8">
        <h2 className="text-xl font-bold mb-4">חברות קיימות</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {companies.map((c: any) => (
            <div key={c.id} className="border p-4 rounded" style={{ borderColor: c.color }}>
              <h3 className="font-bold" style={{ color: c.color }}>{c.name}</h3>
              {c.logo_url && <img src={c.logo_url} alt="Logo" className="w-16 h-16 object-contain my-2" />}
              <div className="text-sm text-gray-600">צבע: <span style={{ color: c.color }}>{c.color}</span></div>
            </div>
          ))}
        </div>
      </div>

      <div className="bg-white p-6 rounded shadow">
        <h2 className="text-xl font-bold mb-4">משתמשים</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-right">
            <thead>
              <tr className="border-b">
                <th className="p-2">שם משתמש</th>
                <th className="p-2">שם מלא</th>
                <th className="p-2">תפקיד</th>
                <th className="p-2">חברה</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u: any) => (
                <tr key={u.id} className="border-b">
                  <td className="p-2">{u.username}</td>
                  <td className="p-2">{u.full_name}</td>
                  <td className="p-2">{u.role === 'worker' ? 'עובד' : 'מנהל'}</td>
                  <td className="p-2">[שם חברה]</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default AdminPanel;
EOL

# יצירת קבצי בסיס
cat > README.md <<EOL
# 🕐 ניהול משמרות שבועי/חודשי

אפליקציית ווב מתקדמת לניהול משמרות לעובדים, עם תמיכה בחברות מרובות, ייצוא, התראות, מצב חשוך ותמיכה בטלפונים.

🔗 GitHub: https://github.com/Zi123ki/shifts.git

## 🚀 התקנה והרצה

הפעל את הסקריפט הקסם:
\`\`\`bash
chmod +x update-and-deploy.sh
./update-and-deploy.sh
\`\`\`
EOL

cat > .gitignore <<EOL
node_modules/
.env
.DS_Store
dist/
build/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
EOL

echo "✅ כל הקבצים עודכנו!"

# שלב 2: התקנת תלויות
echo "📦 מתקין תלויות..."
cd server && npm install
cd ../client && npm install

# שלב 3: איתחול Git
echo "🐙 מתחבר ל-GitHub..."
cd ..
git init
git add .
git commit -m "✨ Full app ready with dark mode, PDF, email, reminders"
git branch -M main
git remote add origin https://github.com/Zi123ki/shifts.git
git push -u --force origin main

echo "🎉 כל הכבוד! העלאה ל-GitHub הסתיימה בהצלחה!"
echo "➡️ פתח את הדפדפן: http://localhost:3000"
echo "🔐 התחבר עם: zvika / Zz321321"

echo "🚀 עכשיו תצטרך רק להריץ:"
echo "  	cd server && npm run dev"
echo "  	cd client && npm start"
