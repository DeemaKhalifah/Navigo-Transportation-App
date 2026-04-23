require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { initializeFirebase } = require('./config/firebase');
const { errorHandler } = require('./middleware/errorHandler');

// Initialize Firebase Admin SDK
initializeFirebase();

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Routes
app.use('/api/auth', require('./routes/auth.routes'));
app.use('/api/routes', require('./routes/routes.routes'));
app.use('/api/trips', require('./routes/trips.routes'));
app.use('/api/users', require('./routes/users.routes'));

// Health check
app.get('/api/health', (req, res) => {
  res.json({ success: true, message: 'Navigo API is running' });
});

// Global error handler
app.use(errorHandler);

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Navigo backend running on port ${PORT}`);
});

module.exports = app;
