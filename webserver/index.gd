extends RefCounted

const HTML = """<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<title>GodotSauger SFDL Upload</title>
	<style>
		body { font-family: sans-serif; margin: 40px; background: #222; color: #eee; }
		.container { background: #333; padding: 20px; border-radius: 8px; max-width: 900px; margin: 0 auto; }
		input[type=file] { margin: 15px 0; display: block; }
		input[type=submit] { background: #478cbf; color: white; border: none; padding: 10px 15px; border-radius: 4px; cursor: pointer; }
		input[type=submit]:hover { background: #356b93; }
		input[type=submit]:disabled { background: #555; cursor: not-allowed; }
		#message { margin-top: 20px; padding: 10px; border-radius: 4px; display: none; }
		.success { background: #2e7d32; color: #fff; }
		.error { background: #c62828; color: #fff; }
		
		/* Styles für die Log-Box */
		#logConsole {
			margin-top: 30px;
			background: #000;
			border: 1px solid #444;
			padding: 10px;
			height: 300px;
			overflow-y: auto;
			font-family: 'Courier New', monospace;
			font-size: 0.9em;
			border-radius: 4px;
			white-space: pre-wrap;
		}
		.log-entry { margin-bottom: 2px; border-bottom: 1px solid #111; padding-bottom: 2px; }
	</style>
</head>
<body>
	<div class="container">
		<h1>GodotSauger</h1>
		<h2>SFDL Upload</h2>
		<form id="uploadForm">
			<label>Select SFDL file:</label>
			<input type="file" id="xml_file" name="sfdl_file" accept=".sfdl" required>
			<input type="submit" id="submitBtn" value="Upload">
		</form>
		<div id="message"></div>
		
		<!-- Log Bereich -->
		<h3>Live Server Logs</h3>
		<div id="logConsole"></div>
	</div>

	<script>
		// --- Bestehende Upload Logik ---
		const form = document.getElementById('uploadForm');
		const messageDiv = document.getElementById('message');
		const submitBtn = document.getElementById('submitBtn');
		
		form.addEventListener('submit', function(e) {
			e.preventDefault();
			messageDiv.style.display = 'none';
			submitBtn.disabled = true;
			submitBtn.value = 'Uploading ...';
			const formData = new FormData(form);
			fetch('/', {
				method: 'POST',
				body: formData
			})
			.then(async response => {
				const text = await response.text();
				messageDiv.style.display = 'block';
				if (response.ok) {
					messageDiv.className = 'success';
					messageDiv.innerHTML = text;
					form.reset();
				} else {
					messageDiv.className = 'error';
					messageDiv.innerHTML = 'Error: ' + text;
				}
			})
			.catch(error => {
				messageDiv.style.display = 'block';
				messageDiv.className = 'error';
				messageDiv.innerHTML = 'Network error';
			})
			.finally(() => {
				submitBtn.disabled = false;
				submitBtn.value = 'Upload';
			});
		});

		// --- NEU: SSE Log Streaming Logik ---
		const logConsole = document.getElementById('logConsole');
		const eventSource = new EventSource('/logs');

		eventSource.onmessage = function(event) {
			const entry = document.createElement('div');
			entry.className = 'log-entry';
			entry.innerHTML = event.data; // Erwartet HTML vom Server
			logConsole.appendChild(entry);
			
			// Auto-Scroll nach unten
			logConsole.scrollTop = logConsole.scrollHeight;
		};

		eventSource.onerror = function(err) {
			console.error("SSE connection lost. Retrying...");
		};
	</script>
</body>
</html>"""
