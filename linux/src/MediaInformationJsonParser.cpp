/*
 * Copyright (c) 2025 Akash Patel
 *
 * This file is part of FFmpegKit.
 *
 * FFmpegKit is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FFmpegKit is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with FFmpegKit.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "MediaInformationJsonParser.h"
#include <json/json.h>
#include <memory>
#include <iostream>

static const char* MediaInformationJsonParserKeyStreams =  "streams";
static const char* MediaInformationJsonParserKeyChapters = "chapters";

std::shared_ptr<ffmpegkit::MediaInformation> ffmpegkit::MediaInformationJsonParser::from(const std::string& ffprobeJsonOutput) {
    try {
        return fromWithError(ffprobeJsonOutput);
    } catch(const std::exception& exception) {
        std::cout << "MediaInformation parsing failed: " << exception.what() << std::endl;
        return nullptr;
    }
}

std::shared_ptr<ffmpegkit::MediaInformation> ffmpegkit::MediaInformationJsonParser::fromWithError(const std::string& ffprobeJsonOutput) {
    Json::Value root;
    Json::CharReaderBuilder readerBuilder;
    std::unique_ptr<Json::CharReader> reader(readerBuilder.newCharReader());
    
    std::string errors;
    bool parsingSuccessful = reader->parse(ffprobeJsonOutput.c_str(), 
                                          ffprobeJsonOutput.c_str() + ffprobeJsonOutput.length(), 
                                          &root, 
                                          &errors);

    if (!parsingSuccessful) {
        throw std::runtime_error("JSON parse error: " + errors);
    }

    std::shared_ptr<std::vector<std::shared_ptr<ffmpegkit::StreamInformation>>> streams = 
        std::make_shared<std::vector<std::shared_ptr<ffmpegkit::StreamInformation>>>();
    std::shared_ptr<std::vector<std::shared_ptr<ffmpegkit::Chapter>>> chapters = 
        std::make_shared<std::vector<std::shared_ptr<ffmpegkit::Chapter>>>();

    if (root.isMember(MediaInformationJsonParserKeyStreams)) {
        Json::Value& streamArray = root[MediaInformationJsonParserKeyStreams];
        if (streamArray.isArray()) {
            for (Json::ArrayIndex i = 0; i < streamArray.size(); i++) {
                auto stream = std::make_shared<Json::Value>();
                *stream = streamArray[i];
                streams->push_back(std::make_shared<ffmpegkit::StreamInformation>(stream));
            }
        }
    }

    if (root.isMember(MediaInformationJsonParserKeyChapters)) {
        Json::Value& chapterArray = root[MediaInformationJsonParserKeyChapters];
        if (chapterArray.isArray()) {
            for (Json::ArrayIndex i = 0; i < chapterArray.size(); i++) {
                auto chapter = std::make_shared<Json::Value>();
                *chapter = chapterArray[i];
                chapters->push_back(std::make_shared<ffmpegkit::Chapter>(chapter));
            }
        }
    }

    return std::make_shared<ffmpegkit::MediaInformation>(
        std::make_shared<Json::Value>(root), 
        streams, 
        chapters
    );
}