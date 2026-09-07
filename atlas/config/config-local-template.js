define([], function () {
	var configLocal = {};
	configLocal.api = {
		name: 'Local OHDSI Instance',
		url: 'http://localhost:8280/WebAPI/'
	};
	return configLocal;
});