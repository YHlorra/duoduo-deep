/// JSON schemas for structured output validation.
///
/// Used with OpenAI structured outputs / JSON schema mode.
const deckSchemaName = 'deck_schema';

const deckJsonSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['concepts', 'title', 'questions'],
  'properties': {
    'concepts': {
      'type': 'array',
      'items': {'type': 'string', 'minLength': 1},
      'minItems': 1,
      'maxItems': 50,
    },
    'title': {
      'type': 'string',
      'minLength': 1,
      'maxLength': 100,
    },
    'questions': {
      'type': 'array',
      'minItems': 5,
      'maxItems': 10,
      'items': {'\$ref': '#/\$defs/question'},
    },
  },
  '\$defs': {
    'question': {
      'type': 'object',
      'additionalProperties': false,
      'required': [
        'type',
        'content',
        'difficulty',
        'cognitiveLevel',
        'answer',
        'explanation',
      ],
      'properties': {
        'type': {
          'type': 'string',
          'enum': [
            'multiple_choice',
            'fill_blank',
            'true_false',
            'matching',
            'ordering',
          ],
        },
        'content': {'type': 'string', 'minLength': 1},
        'difficulty': {
          'type': 'string',
          'enum': ['easy', 'medium', 'hard'],
        },
        'cognitiveLevel': {
          'type': 'string',
          'enum': ['knowledge', 'skill'],
        },
        'options': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 2,
        },
        'answer': {'type': 'string'},
        'explanation': {'type': 'string'},
        'match_left': {'type': 'array', 'items': {'type': 'string'}},
        'match_right': {'type': 'array', 'items': {'type': 'string'}},
      },
    },
  },
};

const socraticEvaluationSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['understood'],
  'properties': {
    'understood': {'type': 'boolean'},
    'hint': {'type': 'string'},
  },
};

/// Schema for the concept-parsing / structuring intermediate step.
///
/// Phase 1.5 of the deep pipeline: raw search results → structured knowledge.
/// Smaller output than a full deck, so max_tokens 4096 is sufficient here.
const searchResultsSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['concepts', 'summary'],
  'properties': {
    'concepts': {
      'type': 'array',
      'items': {'\$ref': '#/\$defs/concept'},
      'minItems': 0,
      'maxItems': 30,
    },
    'summary': {'type': 'string', 'minLength': 0, 'maxLength': 500},
  },
  '\$defs': {
    'concept': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['name', 'description'],
      'properties': {
        'name': {'type': 'string', 'minLength': 1, 'maxLength': 100},
        'description': {'type': 'string', 'minLength': 0, 'maxLength': 500},
        'keyPoints': {
          'type': 'array',
          'items': {'type': 'string'},
          'maxItems': 10,
        },
      },
    },
  },
};

const fillBlankJudgeSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['correct'],
  'properties': {
    'correct': {'type': 'boolean'},
    'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
  },
};

/// Phase 2a: question plan schema — small, bounded output.
const questionPlanSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['plan'],
  'properties': {
    'plan': {
      'type': 'array',
      'minItems': 3,
      'maxItems': 10,
      'items': {'\$ref': '#/\$defs/questionStub'},
    },
  },
  '\$defs': {
    'questionStub': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['type', 'difficulty', 'cognitiveLevel', 'concept', 'briefContent'],
      'properties': {
        'type': {
          'type': 'string',
          'enum': ['multiple_choice', 'fill_blank', 'true_false', 'matching', 'ordering'],
        },
        'difficulty': {'type': 'string', 'enum': ['easy', 'medium', 'hard']},
        'cognitiveLevel': {'type': 'string', 'enum': ['knowledge', 'skill']},
        'concept': {'type': 'string', 'minLength': 1, 'maxLength': 100},
        'briefContent': {'type': 'string', 'minLength': 1, 'maxLength': 200},
      },
    },
  },
};

/// Phase 2b: batch expansion schema — expands 2-3 stubs into full questions.
const questionBatchSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['questions'],
  'properties': {
    'concepts': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'questions': {
      'type': 'array',
      'minItems': 1,
      'maxItems': 3,
      'items': {'\$ref': '#/\$defs/question'},
    },
  },
  '\$defs': {
    'question': <String, dynamic>{
      'type': 'object',
      'additionalProperties': false,
      'required': [
        'type',
        'content',
        'difficulty',
        'cognitiveLevel',
        'answer',
        'explanation',
      ],
      'properties': {
        'type': {
          'type': 'string',
          'enum': [
            'multiple_choice',
            'fill_blank',
            'true_false',
            'matching',
            'ordering',
          ],
        },
        'content': {'type': 'string', 'minLength': 1},
        'difficulty': {
          'type': 'string',
          'enum': ['easy', 'medium', 'hard'],
        },
        'cognitiveLevel': {
          'type': 'string',
          'enum': ['knowledge', 'skill'],
        },
        'options': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 2,
        },
        'answer': {'type': 'string'},
        'explanation': {'type': 'string'},
        'match_left': {'type': 'array', 'items': {'type': 'string'}},
        'match_right': {'type': 'array', 'items': {'type': 'string'}},
      },
    },
  },
};
