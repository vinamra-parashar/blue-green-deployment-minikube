document.addEventListener('DOMContentLoaded', function() {
    // Form steps navigation
    const progress = document.getElementById('progress');
    const formSteps = document.querySelectorAll('.form-step');
    const steps = document.querySelectorAll('.step');
    
    let currentStep = 1;
    
    // Next buttons
    document.getElementById('next1').addEventListener('click', () => {
      // Validate fields in step 1
      const name = document.getElementById('name').value;
      const surname = document.getElementById('surname').value;
      const dob = document.getElementById('dob').value;
      
      if (!name || !surname || !dob) {
        showMessage('Please fill all fields before proceeding', 'error');
        return;
      }
      
      goToStep(2);
    });
    
    document.getElementById('next2').addEventListener('click', () => {
      // Validate fields in step 2
      const job = document.getElementById('job').value;
      const place = document.getElementById('place').value;
      
      if (!job || !place) {
        showMessage('Please fill all fields before proceeding', 'error');
        return;
      }
      
      goToStep(3);
    });
    
    // Previous buttons
    document.getElementById('prev2').addEventListener('click', () => {
      goToStep(1);
    });
    
    document.getElementById('prev3').addEventListener('click', () => {
      goToStep(2);
    });
    
    function goToStep(step) {
      formSteps.forEach(formStep => {
        formStep.classList.remove('active');
      });
      
      document.getElementById(`step${step}`).classList.add('active');
      
      // Update progress bar and steps
      steps.forEach((stepEl, idx) => {
        if (idx < step) {
          stepEl.classList.add('completed');
          stepEl.classList.add('active');
        } else if (idx === step - 1) {
          stepEl.classList.remove('completed');
          stepEl.classList.add('active');
        } else {
          stepEl.classList.remove('completed');
          stepEl.classList.remove('active');
        }
      });
      
      // Calculate progress width
      const progressWidth = ((step - 1) / (steps.length - 1)) * 100;
      progress.style.width = `${progressWidth}%`;
      
      currentStep = step;
    }
    
    // Prevent form submission when pressing Enter in step 1 & 2 inputs
    document.querySelectorAll('#step1 input').forEach(input => {
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          document.getElementById('next1').click();
        }
      });
    });

    document.querySelectorAll('#step2 input').forEach(input => {
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          document.getElementById('next2').click();
        }
      });
    });
    
    // Tag input for interests
    const interestInput = document.getElementById('interestInput');
    const interestTags = document.getElementById('interestTags');
    const interestsHidden = document.getElementById('interests');
    
    let interests = [];
    
    function processInputTags(inputEl, container, array, hiddenField) {
      const rawValue = inputEl.value.trim();
      if (!rawValue) return;

      const items = rawValue
        .split(',')
        .map(item => item.trim())
        .filter(item => item.length > 0);

      items.forEach(item => {
        if (!array.includes(item)) {
          addTag(item, container, array);
        }
      });

      updateHiddenField(hiddenField, array);
      inputEl.value = '';
    }

    interestInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ',') {
        e.preventDefault();
        processInputTags(interestInput, interestTags, interests, interestsHidden);
      }
    });

    interestInput.addEventListener('blur', () => {
      processInputTags(interestInput, interestTags, interests, interestsHidden);
    });
    
    // Tag input for languages
    const languageInput = document.getElementById('languageInput');
    const languageTags = document.getElementById('languageTags');
    const languagesHidden = document.getElementById('knownLanguages');
    
    let languages = [];
    
    languageInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ',') {
        e.preventDefault();
        processInputTags(languageInput, languageTags, languages, languagesHidden);
      }
    });

    languageInput.addEventListener('blur', () => {
      processInputTags(languageInput, languageTags, languages, languagesHidden);
    });
    
    function addTag(text, container, array) {
      const tag = document.createElement('span');
      tag.classList.add('tag');
      tag.innerHTML = `${text} <i class="fas fa-times"></i>`;
      
      // Remove tag on click
      tag.querySelector('i').addEventListener('click', () => {
        container.removeChild(tag);
        const index = array.indexOf(text);
        if (index !== -1) {
          array.splice(index, 1);
          if (container === interestTags) {
            updateHiddenField(interestsHidden, interests);
          } else {
            updateHiddenField(languagesHidden, languages);
          }
        }
      });
      
      container.appendChild(tag);
      array.push(text);
    }
    
    function updateHiddenField(hiddenField, array) {
      hiddenField.value = JSON.stringify(array);
    }
    
    // Form submission
    document.getElementById('registrationForm').addEventListener('submit', async function(e) {
      e.preventDefault();

      // Automatically commit any text currently in the inputs before validating
      processInputTags(interestInput, interestTags, interests, interestsHidden);
      processInputTags(languageInput, languageTags, languages, languagesHidden);
      
      if (interests.length === 0 || languages.length === 0) {
        showMessage('Please add at least one interest and language', 'error');
        return;
      }
      
      const formData = {
        name: document.getElementById('name').value,
        surname: document.getElementById('surname').value,
        dob: document.getElementById('dob').value,
        job: document.getElementById('job').value,
        place: document.getElementById('place').value,
        interests: interests,
        knownLanguages: languages,
        registeredFrom: 'enhanced'
      };
      
      try {
        const response = await fetch('http://localhost:5000/api/users', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(formData)
        });
        
        if (response.ok) {
          const result = await response.json();
          showMessage('Registration successful!', 'success');
          document.getElementById('registrationForm').reset();
          interestTags.innerHTML = '';
          languageTags.innerHTML = '';
          interests = [];
          languages = [];
          updateHiddenField(interestsHidden, interests);
          updateHiddenField(languagesHidden, languages);
          goToStep(1);
        } else {
          const error = await response.json();
          showMessage(`Error: ${error.message}`, 'error');
        }
      } catch (error) {
        showMessage(`Server error: ${error.message}`, 'error');
      }
    });
    
    // Show message function
    function showMessage(text, type) {
      const messageContainer = document.getElementById('message');
      messageContainer.innerHTML = text;
      messageContainer.className = 'message-container';
      messageContainer.classList.add(type);
      messageContainer.style.display = 'block';
      
      // Auto hide after 5 seconds
      setTimeout(() => {
        messageContainer.style.display = 'none';
      }, 5000);
    }
  });
