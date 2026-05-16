(function () {
  const form = document.getElementById('launch-list-form');
  const status = document.getElementById('launch-status');

  if (!form || !status) return;

  function setStatus(message, state) {
    status.textContent = message;
    status.dataset.state = state || '';
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    setStatus('', '');

    const submitButton = form.querySelector('button[type="submit"]');
    const formData = new FormData(form);
    const payload = {
      fullName: String(formData.get('fullName') || ''),
      email: String(formData.get('email') || ''),
      phoneNumber: String(formData.get('phoneNumber') || ''),
      company: String(formData.get('company') || ''),
      sourcePage: 'launch-list',
    };

    submitButton.disabled = true;
    submitButton.textContent = 'Joining...';

    try {
      const response = await fetch('/api/launch-list/', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });

      const result = await response.json().catch(() => ({}));

      if (!response.ok) {
        setStatus(result.error || 'We could not save your signup right now.', 'error');
        return;
      }

      form.reset();
      setStatus(result.message || 'You are on the launch list.', 'success');
    } catch {
      setStatus('Something went wrong. Please try again in a moment.', 'error');
    } finally {
      submitButton.disabled = false;
      submitButton.textContent = 'Join the launch list';
    }
  });
})();
