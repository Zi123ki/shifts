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
    axios.defaults.headers.common['Authorization'] = `Bearer ${token}`;
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
