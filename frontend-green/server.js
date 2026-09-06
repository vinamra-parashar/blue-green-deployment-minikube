const express = require('express');
const path = require('path');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3200;

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'ok', 
    message: 'Green frontend is running', 
    version: 'green' 
  });
});

app.listen(PORT, () => {
  console.log(`Green frontend server running on port ${PORT}`);
});