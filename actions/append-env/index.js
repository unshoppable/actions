const fs = require('fs');
const path = require('path');
const core = require('@actions/core');
const { execSync } = require('child_process');

try {
  const fileName = core.getInput('filename', { required: true });
  const masked = (core.getInput('masked') || 'false') === 'true';
  const envFilePath = '/etc/environment';

  const fullPath = path.resolve(fileName);
  core.info(`Processing file: ${fullPath}`);

  const rawdata = fs.readFileSync(fullPath);
  const rootObj = JSON.parse(rawdata);

  const processVariable = (variable, name) => {
    if (typeof variable === 'undefined' || variable === null) {
      return;
    }

    if (Array.isArray(variable)) {
      variable.forEach((value, index) => {
        processVariable(value, name ? `${name}_${index}` : index);
      });
    }
    else if (typeof variable === 'object') {
      for (const field in variable) {
        processVariable(variable[field], name ? `${name}_${field}` : field);
      }
    }
    else {
      if (masked) {
        core.setSecret(variable);
      }

      const upperCaseName = name.toUpperCase();

      core.info(`SET ENV '${upperCaseName}' = ${variable}`);
      core.exportVariable(upperCaseName, variable.toString());

      const envEntry = `${upperCaseName}=${variable}`;
      execSync(`echo '${envEntry}' | sudo tee -a ${envFilePath}`);
    }
  };

  processVariable(rootObj, '');

} catch (error) {
  core.setFailed(error.message);
}
