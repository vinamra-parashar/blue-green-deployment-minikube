const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true
  },
  surname: {
    type: String,
    required: true
  },
  dob: {
    type: Date,
    required: true
  },
  job: {
    type: String,
    required: true
  },
  place: {
    type: String,
    required: true
  },
  interests: {
    type: [String],
    required: true
  },
  knownLanguages: {
    type: [String],
    required: true
  },
  registrationDate: {
    type: Date,
    default: Date.now
  },
  registeredFrom: {
    type: String,
    enum: ['basic', 'enhanced'],
    required: true
  }
});

module.exports = mongoose.model('User', userSchema);