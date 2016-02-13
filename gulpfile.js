'use strict';

const _ = require('lodash');
const gulp = require('gulp');
const rename = require('gulp-rename');
const solc = require('solc');
const through = require('through-gulp');

gulp.task('default', () => {
  return gulp
    .src(['**/*.sol'])
    .pipe(through(function(file, encoding, callback) {
      const importrx = /import "([\_\-\.\/a-zA-Z0-9]*)";/g;
      const sources = {};
      const filedata = file.contents.toString();
      sources[file.relative] = filedata;

      let match = importrx.exec(filedata);

      while (match) {
        sources[match[1]] = fs.readFileSync(path.join('.', match[1])).toString();
        match = importrx.exec(filedata);
      }

      const output = solc.compile({ sources: sources }, 1);

      if (output.errors) {
        console.error(`error compiling ${file.relative}`);
        _.each(output.errors, (err) => {
          console.error(err);
        });
        callback();
        return;
      }

      _.each(output.contracts, (contract, name) => {
        if (sources[file.relative].indexOf(`contract ${name} `) !== -1) {
          file.contents = new Buffer(JSON.stringify({
            // solidity: contract.solidity_interface,
            // runtime: contract.runtimeBytecode
            size: contract.bytecode.length,
            bytecode: contract.bytecode,
            estimates: contract.gasEstimates,
            interface: JSON.parse(contract.interface)
          }, null, 2), 'utf-8');
        }
      });

      this.push(file);
      callback();
    },
    function(callback) {
      callback();
    }))
    .pipe(rename((file) => {
      file.extname = '.json';
    }))
    .pipe(gulp.dest('dist/'));
});
