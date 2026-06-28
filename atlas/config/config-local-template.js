define([], function () {
	var configLocal = {};
	configLocal.api = {
		name: 'Local OHDSI Instance',
		url: 'http://localhost:8080/WebAPI/'
	};
	return configLocal;
});