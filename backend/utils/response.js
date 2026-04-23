/**
 * Standard JSON response helpers.
 */

function success(res, data, message = 'Success', statusCode = 200) {
  return res.status(statusCode).json({
    success: true,
    data,
    message,
  });
}

function error(res, message = 'Error', statusCode = 400, code = null) {
  return res.status(statusCode).json({
    success: false,
    error: message,
    code,
  });
}

function created(res, data, message = 'Created successfully') {
  return success(res, data, message, 201);
}

module.exports = { success, error, created };
