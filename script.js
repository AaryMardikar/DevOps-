const form = document.getElementById("feedbackForm");
const message = document.getElementById("formMessage");

function showError(id, text) {
  document.getElementById(id).textContent = text;
}

function clearErrors() {
  [
    "studentNameError",
    "emailError",
    "mobileError",
    "departmentError",
    "genderError",
    "commentsError"
  ].forEach((id) => showError(id, ""));
}

function validateForm() {
  clearErrors();
  let valid = true;

  const studentName = form.studentName.value.trim();
  const email = form.email.value.trim();
  const mobile = form.mobile.value.trim();
  const department = form.department.value;
  const gender = form.querySelector("input[name='gender']:checked");
  const comments = form.comments.value.trim();

  if (!studentName) {
    showError("studentNameError", "Student name should not be empty.");
    valid = false;
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    showError("emailError", "Enter a valid email address.");
    valid = false;
  }

  if (!/^\d{10}$/.test(mobile)) {
    showError("mobileError", "Enter a valid 10-digit mobile number.");
    valid = false;
  }

  if (!department) {
    showError("departmentError", "Please select your department.");
    valid = false;
  }

  if (!gender) {
    showError("genderError", "Please select your gender.");
    valid = false;
  }

  if (!comments) {
    showError("commentsError", "Feedback comments should not be blank.");
    valid = false;
  }

  return valid;
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  message.className = "message";

  if (validateForm()) {
    message.textContent = "Feedback submitted successfully.";
  } else {
    message.textContent = "Please fix the errors";
  }
});

form.addEventListener("reset", () => {
  clearErrors();
  message.textContent = "Form reset successfully.";
});