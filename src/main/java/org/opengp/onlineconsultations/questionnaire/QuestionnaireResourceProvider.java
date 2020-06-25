package org.opengp.onlineconsultations.questionnaire;

import org.hl7.fhir.r4.model.IdType;
import org.hl7.fhir.r4.model.Questionnaire;
import org.springframework.stereotype.Component;

import ca.uhn.fhir.rest.annotation.IdParam;
import ca.uhn.fhir.rest.annotation.Read;
import ca.uhn.fhir.rest.server.IResourceProvider;

@Component
public class QuestionnaireResourceProvider implements IResourceProvider{

    @Override
    public Class<Questionnaire> getResourceType() {
        return Questionnaire.class;
    }

    @Read
    public Questionnaire find(@IdParam final IdType theId) {
        return new Questionnaire();
    }
    
}