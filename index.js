'use strict';

function loadNativeConstructor() {
  return require('./native.js').AvlTree;
}

module.exports = loadNativeConstructor();
