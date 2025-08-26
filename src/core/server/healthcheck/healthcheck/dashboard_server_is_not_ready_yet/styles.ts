/* eslint-disable @osd/eslint/require-license-header */
export const styles = /* css */ `
.text-danger {
  color: red;
}
.text-warn {
  color: #ff8c00;
}
.btn {
  background-color: transparent;
  color: #e57373; /* Light red */
  border: 2px solid #e57373;
  padding: 5px 10px;
  font-size: 16px;
  border-radius: 4px;
  cursor: pointer;
  transition: background-color 0.3s ease, color 0.3s ease;
}
.btn:disabled,
.btn[disabled] {
  cursor: not-allowed;
  opacity: 0.7;
}

.btn-run-failed-critical-checks {
  color: #e57373; /* Light red */
  border: 2px solid #e57373;
}
.btn-run-failed-critical-checks:hover {
  background-color: #e57373;
  color: white;
}
.btn-run-failed-critical-checks:disabled,
.btn-run-failed-critical-checks[disabled] {
  background-color: #f8d7da; /* Light red background */
  color: #a1a1a1; /* Muted text color */
  border: 2px solid #f5c2c7; /* Soft border */
}

.btn-export-checks {
  color: #3595f9; /* Light red */
  border: 2px solid #3595f9;
}
.btn-export-checks:hover {
  background-color: #3595f9;
  color: white;
}
.btn-export-checks:disabled,
.btn-export-checks[disabled] {
  background-color: #f8d7da; /* Light red background */
  color: #a1a1a1; /* Muted text color */
  border: 2px solid #f5c2c7; /* Soft border */
}

pre.code,
code.code {
  background-color: #f5f5f5; /* light gray */
  color: #333; /* dark text for contrast */
  font-family: Consolas, Monaco, 'Courier New', monospace;
  font-size: 14px;
  padding: 10px;
  border-radius: 5px;
  overflow-x: auto;
  display: block;
  white-space: pre-wrap;
}

.d-flex {
  display: flex;
}

.d-jc-center {
  justify-content: center;
}

.d-ai-center {
  align-items: center;
}

.d-gap-m {
  gap: 10px;
}

.margin-m {
  margin: 10px;
}

.padding-m {
  padding: 10px;
}
`;
