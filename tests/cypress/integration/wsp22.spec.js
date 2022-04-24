/// <reference types="cypress" />
// wsp22.spec.js created with Cypress
//
// Start writing your Cypress tests below!
// If you're unfamiliar with how Cypress works,
// check out the link below and learn how to write your first test:
// https://on.cypress.io/writing-first-test
import { url } from "../support/functions";

let email = `cypress-test-${new Date().getTime()}@svaren.dev`;

describe("WSP22 - create account", () => {
    it("should be able register", () => {
        cy.visit(url("register"));
        cy.get("[name=name]").type("Cypress");
        cy.get("[name=email]").type(email);
        cy.get("[name=postal_code]").type("11122");
        cy.get("[name=password]").type("password");
        cy.get("[name=confirm-password]").type("password");
        cy.get("form").submit();
    });

    it("should be able to log in", () => {
        cy.visit(url("login"));
        cy.get("[name=email]").type(email);
        cy.get("[name=password]").type("password");
        cy.get("form").submit();
    });
});

describe("WSP22 - logged in", () => {
    let created_id;

    beforeEach(() => {
        cy.login(email);
    });

    it("should be able to create listing", () => {
        cy.visit(url("listing/new"));
        cy.get("[name=title]").type("Cypress test");
        cy.get("[name=price]").type("100");
        cy.get("[name=content]").type("Cypress test listing description");
        cy.get("form").submit();
        console.log(cy.location("href").toString());
        cy.location("href").then(url => {
            created_id = url.match(/\/listing\/(\d+)/)[1];
        });
    });

    it("should be able to edit listing", () => {
        cy.visit(url(`listing/${created_id}/edit`));
        cy.get("[name=title]").clear().type("Cypress edited");
        cy.get("[name=price]").clear().type("0");
        cy.get("[name=content]").clear().type("Cypress test listing description - edited");
        // cy.readFile("cypress/fixtures/picture.jpg", null).then(picture => {
        //     cy.get("[type=file]").selectFile(picture);
        // });
        cy.get("form").submit();

        cy.location("href").should("contain", `listing/${created_id}`);
        cy.get(".price").should("have.text", "Gratis");
        cy.get(".card-title h1").should("have.text", "Cypress edited");
        cy.get(".description").should("have.text", "Cypress test listing description - edited");
    });

    it("should be able to mark as sold", () => {
        cy.visit(url(`listing/${created_id}`));
        cy.get(`form[action="/listing/${created_id}/sold"]`).submit();
        cy.visit(url("search"));
        cy.get(`a[href="/listing/${created_id}"]`).should("not.exist");
    });
});

describe("WSP22 - logged out", () => {
    it("can view all listings", () => {
        cy.visit(url("search")).then(r => console.log(r.status));
        //.should(r => expect(r).property("status").to.eq(200))
    });
});
