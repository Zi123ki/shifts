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
    axios.defaults.headers.common['Authorization'] = `Bearer ${token}`;
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
          `שלום ${shift.users?.full_name}, יש לך משמרת מחר (${shift.date}) בין ${shift.hours}`
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
        className={`p-1 rounded text-white text-xs min-h-8 flex flex-col justify-center ${darkMode ? 'bg-opacity-80' : ''}`}
      >
        <div className="font-bold">{shift?.hours}</div>
        {shift?.notes && <div className="text-[10px]">({shift.notes})</div>}
        <div className="text-[9px] mt-1">{shift?.users?.full_name}</div>
      </div>
    );
  };

  const events = shifts.map(shift => ({
    id: shift.id,
    title: `${shift.hours} (${shift.users?.full_name || 'N/A'})`,
    start: shift.date,
    backgroundColor: shift.color,
    extendedProps: shift
  }));

  if (loading) {
    return <div className="flex items-center justify-center min-h-screen">טוען...</div>;
  }

  if (!company) {
    return (
      <div className={`p-4 text-center ${darkMode ? 'bg-gray-900 text-white' : 'bg-white'}`}>
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
    <div className={`min-h-screen ${darkMode ? 'bg-gray-900 text-white' : 'bg-gray-50 text-gray-900'}`}>
      <div className={`md:hidden p-4 shadow-sm flex justify-between items-center ${darkMode ? 'bg-gray-800' : 'bg-white'}`}>
        <h1 className="text-lg font-bold" style={{ color: company.color || '#3B82F6' }}>
          {company.name}
        </h1>
        <div className="flex gap-2 items-center">
          <button
            onClick={toggleDarkMode}
            className={`p-2 rounded ${darkMode ? 'bg-yellow-400 text-gray-900' : 'bg-gray-700 text-white'}`}
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

      <div className={`hidden md:flex justify-between items-center p-6 shadow-sm ${darkMode ? 'bg-gray-800' : 'bg-white'}`}>
        <h1 className="text-2xl font-bold" style={{ color: company.color || '#3B82F6' }}>
          {company.name} - לוח משמרות
        </h1>
        <div className="flex gap-4 items-center">
          <button
            onClick={toggleDarkMode}
            className={`p-2 rounded-full ${darkMode ? 'bg-yellow-400 text-gray-900' : 'bg-gray-700 text-white'}`}
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
        <div className={`p-4 rounded shadow ${darkMode ? 'bg-gray-800' : 'bg-white'}`}>
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
