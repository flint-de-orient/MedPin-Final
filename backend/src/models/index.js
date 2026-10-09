// Registers every MedPin model. `require('./models')` gives you all of them.
module.exports = {
  ...require('./identity'),
  ...require('./practice'),
  ...require('./doctor'),
  ...require('./patient'),
  ...require('./scheduling'),
  ...require('./clinical'),
  ...require('./records'),
  ...require('./messaging'),
  ...require('./commerce'),
  ...require('./system'),
};
