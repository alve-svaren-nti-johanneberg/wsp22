const entry = Cypress.env("APP_ENTRY") || "http://127.0.0.1:4567";

const url = path => `${entry}/${path}`;
const email = () => `cypress-test-${(new Date()).getTime()}@svaren.dev`;


export { url, email };