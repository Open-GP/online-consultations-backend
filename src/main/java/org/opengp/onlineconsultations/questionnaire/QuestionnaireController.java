package org.opengp.onlineconsultations.questionnaire;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class QuestionnaireController {

    @GetMapping("/questionnaire")
    public QuestionnaireModel get() {
        return new QuestionnaireModel("Sample questionnaire");
    }

}
